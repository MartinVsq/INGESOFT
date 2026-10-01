<#
.SYNOPSIS
    Instala el entorno de desarrollo para un proyecto Next.js full-stack
    (App Router + Route Handlers, Prisma, PostgreSQL en Docker, Tailwind) en Windows.

.DESCRIPTION
    Paso 1 - Diagnóstico (no instala nada).
    Paso 2 - Instalación de lo que falte: VS Code, Node.js LTS, Git, WSL 2 (sin distro), Docker Desktop.
    Paso 3 - Extensiones de VS Code.
    Paso 4 - Carpeta C:\Dev\Proyectos (fuera de OneDrive).
    Paso 5 - Verificación final (versiones, hello-world, postgres:16, espacio libre).

    Pide confirmación antes de cada instalación. Usa las rutas por defecto de cada programa.
    Se puede volver a ejecutar sin problema: lo que ya está instalado se omite.

.PARAMETER DesdePaso
    Paso desde el que empezar (1-5). Útil para continuar después de un reinicio
    o después de cerrar y abrir la terminal para refrescar el PATH.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\setup-entorno-windows.ps1
    powershell -ExecutionPolicy Bypass -File .\setup-entorno-windows.ps1 -DesdePaso 3
#>
[CmdletBinding()]
param(
    [ValidateRange(1, 5)]
    [int]$DesdePaso = 1
)

$ErrorActionPreference = 'Continue'
$NombreScript = 'setup-entorno-windows.ps1'
$MinLibreGB = 25
$CarpetaProyectos = 'C:\Dev\Proyectos'
$env:WSL_UTF8 = '1'   # Hace que wsl.exe escriba en UTF-8 en lugar de UTF-16

$Extensiones = @(
    'Prisma.prisma',
    'dbaeumer.vscode-eslint',
    'esbenp.prettier-vscode',
    'bradlc.vscode-tailwindcss',
    'ms-ossdata.vscode-pgsql',
    'ms-azuretools.vscode-docker',
    'humao.rest-client',
    'eamodio.gitlens',
    'usernamehw.errorlens'
)

# ---------------------------------------------------------------------------
# Utilidades
# ---------------------------------------------------------------------------

function Escribir-Titulo([string]$Texto) {
    Write-Host ''
    Write-Host ('=' * 72) -ForegroundColor Cyan
    Write-Host "  $Texto" -ForegroundColor Cyan
    Write-Host ('=' * 72) -ForegroundColor Cyan
}

function Escribir-Ok([string]$Texto)    { Write-Host "  [OK]    $Texto" -ForegroundColor Green }
function Escribir-Falta([string]$Texto) { Write-Host "  [FALTA] $Texto" -ForegroundColor Yellow }
function Escribir-Aviso([string]$Texto) { Write-Host "  [AVISO] $Texto" -ForegroundColor Yellow }
function Escribir-Error([string]$Texto) { Write-Host "  [ERROR] $Texto" -ForegroundColor Red }

function Confirmar([string]$Pregunta) {
    while ($true) {
        $r = (Read-Host "$Pregunta [S/N]").Trim()
        if ($r -match '^(s|si|sí|y|yes)$') { return $true }
        if ($r -match '^(n|no)$') { return $false }
    }
}

# Devuelve 'S' (sí), 'N' (no) o 'T' (sí a todas las restantes)
function Confirmar-ConTodas([string]$Pregunta) {
    while ($true) {
        $r = (Read-Host "$Pregunta [S=sí / N=no / T=sí a todas]").Trim()
        if ($r -match '^(s|si|sí|y|yes)$') { return 'S' }
        if ($r -match '^(n|no)$') { return 'N' }
        if ($r -match '^(t|todas|a|all)$') { return 'T' }
    }
}

function Esperar-Ok([string]$Mensaje) {
    while ($true) {
        $r = (Read-Host "$Mensaje (escribe OK para continuar o SALIR para terminar)").Trim()
        if ($r -match '^ok$') { return }
        if ($r -match '^salir$') { Write-Host 'Saliendo sin cambios adicionales.'; exit 0 }
    }
}

function Actualizar-Path {
    $maquina = [Environment]::GetEnvironmentVariable('Path', 'Machine')
    $usuario = [Environment]::GetEnvironmentVariable('Path', 'User')
    $env:Path = "$maquina;$usuario"
}

function Es-Admin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    return ([Security.Principal.WindowsPrincipal]$id).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Ruta-Comando([string]$Nombre) {
    $r = & where.exe $Nombre 2>$null
    if ($LASTEXITCODE -eq 0 -and $r) { return ($r | Select-Object -First 1) }
    return $null
}

function En-Winget([string]$Id) {
    $null = & winget list -e --id $Id --accept-source-agreements 2>$null
    return ($LASTEXITCODE -eq 0)
}

function Tamano-CarpetaGB([string]$Ruta) {
    if (-not (Test-Path $Ruta)) { return 0 }
    $suma = (Get-ChildItem -LiteralPath $Ruta -Recurse -Force -File -ErrorAction SilentlyContinue |
             Measure-Object -Property Length -Sum).Sum
    if (-not $suma) { return 0 }
    return [math]::Round($suma / 1GB, 2)
}

function Mostrar-Discos {
    Get-PSDrive -PSProvider FileSystem |
        Where-Object { $null -ne $_.Used } |
        Format-Table -AutoSize @(
            @{ Label = 'Unidad';     Expression = { "$($_.Name):" } },
            @{ Label = 'Usado (GB)'; Expression = { [math]::Round($_.Used / 1GB, 1) }; Align = 'Right' },
            @{ Label = 'Libre (GB)'; Expression = { [math]::Round($_.Free / 1GB, 1) }; Align = 'Right' },
            @{ Label = 'Total (GB)'; Expression = { [math]::Round(($_.Used + $_.Free) / 1GB, 1) }; Align = 'Right' }
        ) | Out-Host
}

function Libre-CGB {
    $c = Get-PSDrive -PSProvider FileSystem -Name C
    return [math]::Round($c.Free / 1GB, 1)
}

# --- Versiones (cada función devuelve $null si el programa no responde) ---

function Version-Node   { try { (& node --version 2>$null | Select-Object -First 1) } catch { $null } }
function Version-Npm    { try { (& npm.cmd --version 2>$null | Select-Object -First 1) } catch { $null } }
function Version-Git    { try { ((& git --version 2>$null | Select-Object -First 1) -replace '^git version\s*', '') } catch { $null } }
function Version-Docker { try { ((& docker --version 2>$null | Select-Object -First 1) -replace '^Docker version\s*', '') } catch { $null } }
function Version-Code   { try { (& code.cmd --version 2>$null | Select-Object -First 1) } catch { $null } }

function Version-Wsl {
    try {
        $salida = & wsl.exe --version 2>$null
        if ($LASTEXITCODE -ne 0 -or -not $salida) { return $null }
        $linea = $salida | ForEach-Object { $_ -replace "`0", '' } |
                 Where-Object { $_ -match '\d+\.\d+\.\d+' } | Select-Object -First 1
        if ($linea -match '(\d+\.\d+\.\d+(\.\d+)?)') { return $Matches[1] }
    } catch { }
    return $null
}

function Version-VirtualBox {
    $reg = Get-ItemProperty 'HKLM:\SOFTWARE\Oracle\VirtualBox' -ErrorAction SilentlyContinue
    if ($reg) {
        if ($reg.VersionExt) { return $reg.VersionExt }
        if ($reg.Version)    { return $reg.Version }
    }
    $exe = Join-Path $env:ProgramFiles 'Oracle\VirtualBox\VBoxManage.exe'
    if (Test-Path $exe) { return (& $exe --version | Select-Object -First 1) }
    return $null
}

# Catálogo de programas del Paso 2
$Programas = @(
    [pscustomobject]@{ Nombre = 'VS Code';        Id = 'Microsoft.VisualStudioCode'; Comando = 'code';   Version = ${function:Version-Code} },
    [pscustomobject]@{ Nombre = 'Node.js LTS';    Id = 'OpenJS.NodeJS.LTS';          Comando = 'node';   Version = ${function:Version-Node} },
    [pscustomobject]@{ Nombre = 'Git';            Id = 'Git.Git';                    Comando = 'git';    Version = ${function:Version-Git} },
    [pscustomobject]@{ Nombre = 'WSL 2';          Id = $null;                        Comando = 'wsl';    Version = ${function:Version-Wsl} },
    [pscustomobject]@{ Nombre = 'Docker Desktop'; Id = 'Docker.DockerDesktop';       Comando = 'docker'; Version = ${function:Version-Docker} }
)

function Esta-Instalado($Programa) {
    if ($Programa.Nombre -eq 'WSL 2') {
        # wsl.exe existe siempre en Windows 10/11; solo cuenta como instalado si responde a --version / --status
        if (Version-Wsl) { return $true }
        $null = & wsl.exe --status 2>$null
        return ($LASTEXITCODE -eq 0)
    }
    if (Ruta-Comando $Programa.Comando) { return $true }
    return (En-Winget $Programa.Id)
}

function Verificar-Programa($Programa, [int]$PasoParaContinuar) {
    Actualizar-Path
    $v = & $Programa.Version
    if ($v) {
        Escribir-Ok "$($Programa.Nombre) responde: $v"
        return $true
    }
    Escribir-Aviso "$($Programa.Nombre) no responde todavía con --version."
    Write-Host "          Cierra y vuelve a abrir PowerShell para refrescar el PATH y continúa con:"
    Write-Host "          powershell -ExecutionPolicy Bypass -File .\$NombreScript -DesdePaso $PasoParaContinuar" -ForegroundColor White
    return $false
}

function Instalar-ConWinget($Programa) {
    Write-Host ''
    if (-not (Confirmar "¿Instalar $($Programa.Nombre)?  (winget install -e --id $($Programa.Id))")) {
        Write-Host "  Omitido por ti: $($Programa.Nombre)"
        return
    }
    # Nota: NO se pasa --accept-package-agreements: las licencias de cada programa las aceptas tú.
    & winget install -e --id $Programa.Id --source winget --accept-source-agreements
    if ($LASTEXITCODE -ne 0) {
        Escribir-Aviso "winget terminó con código $LASTEXITCODE. Revisa el mensaje de arriba."
    }
    [void](Verificar-Programa $Programa 2)
}

# ---------------------------------------------------------------------------
# PASO 1 - Diagnóstico
# ---------------------------------------------------------------------------

function Paso1-Diagnostico {
    Escribir-Titulo 'PASO 1 - Diagnóstico (no se instala nada)'

    if (-not (Ruta-Comando 'winget')) {
        Escribir-Error 'winget no está disponible. Instala/actualiza "Instalador de aplicación" (App Installer) desde Microsoft Store y vuelve a ejecutar este script.'
        exit 1
    }

    Write-Host ''
    Write-Host 'Espacio en disco (Get-PSDrive -PSProvider FileSystem):'
    Mostrar-Discos
    $libre = Libre-CGB

    if ($libre -lt $MinLibreGB) {
        Escribir-Aviso "C: tiene $libre GB libres y se recomiendan al menos $MinLibreGB GB."
        Write-Host '          (La instalación ocupa 7-10 GB y los datos de Docker crecen con el uso.)'
        $temp = $env:TEMP
        $descargas = Join-Path $env:USERPROFILE 'Downloads'
        Write-Host ''
        Write-Host '  Sugerencias para liberar espacio:'
        Write-Host '   1. Liberador de espacio en disco: cleanmgr  -> botón "Limpiar archivos del sistema"'
        Write-Host '      (incluye restos de Windows Update, que suelen ocupar varios GB).'
        Write-Host '   2. Configuración > Sistema > Almacenamiento > Archivos temporales.'
        Write-Host "   3. Archivos temporales del usuario: $temp  ($(Tamano-CarpetaGB $temp) GB)"
        Write-Host "   4. Carpeta Descargas: $descargas  ($(Tamano-CarpetaGB $descargas) GB)"
        Write-Host '   5. Papelera de reciclaje y programas que ya no uses (Configuración > Aplicaciones).'
        Write-Host ''
        if (Confirmar '¿Abrir ahora el Liberador de espacio en disco (cleanmgr)?') { Start-Process cleanmgr.exe }
        if (Confirmar '¿Abrir la carpeta de temporales y Descargas en el Explorador para revisarlas?') {
            Start-Process explorer.exe $temp
            Start-Process explorer.exe $descargas
        }
        Write-Host ''
        Write-Host 'Cuando termines de limpiar, vuelve a ejecutar el script para recalcular el espacio.'
        if (-not (Confirmar "¿Quieres continuar de todas formas con solo $libre GB libres?")) { exit 0 }
    } else {
        Escribir-Ok "C: tiene $libre GB libres (mínimo recomendado: $MinLibreGB GB)."
    }

    Write-Host ''
    Write-Host 'Programas (winget list / where.exe):'
    $resumen = foreach ($p in $Programas) {
        $instalado = Esta-Instalado $p
        $version = if ($instalado) { & $p.Version } else { $null }
        $ruta = if ($p.Comando) { Ruta-Comando $p.Comando } else { $null }
        if ($instalado) { Escribir-Ok "$($p.Nombre)  $version" } else { Escribir-Falta $p.Nombre }
        [pscustomobject]@{
            Programa  = $p.Nombre
            Estado    = if ($instalado) { 'Instalado' } else { 'Falta' }
            Version   = if ($version) { $version } else { '-' }
            Ruta      = if ($ruta) { $ruta } else { '-' }
        }
    }

    $vbox = Version-VirtualBox
    if ($vbox) {
        Escribir-Ok "VirtualBox $vbox"
        if ($vbox -match '^(\d+)\.(\d+)') {
            $mayor = [int]$Matches[1]; $menor = [int]$Matches[2]
            if ($mayor -lt 6 -or ($mayor -eq 6 -and $menor -lt 1)) {
                Escribir-Aviso 'Esta versión de VirtualBox NO es compatible con Hyper-V/WSL 2. Actualízala a 7.x antes de instalar WSL/Docker.'
            } else {
                Write-Host '          VirtualBox 6.1+ / 7.x convive con WSL 2, aunque sus VMs pueden ir algo más lentas con Hyper-V activo.'
            }
        }
    } else {
        Write-Host '  [--]    VirtualBox no está instalado (no hay conflicto con WSL 2).'
    }

    Write-Host ''
    Write-Host 'Sincronización con OneDrive:'
    $raicesOneDrive = @($env:OneDrive, $env:OneDriveConsumer, $env:OneDriveCommercial) |
                      Where-Object { $_ } | Select-Object -Unique
    $carpetas = [ordered]@{
        'Documentos' = [Environment]::GetFolderPath('MyDocuments')
        'Escritorio' = [Environment]::GetFolderPath('Desktop')
    }
    $oneDrive = @{}
    foreach ($nombre in $carpetas.Keys) {
        $ruta = $carpetas[$nombre]
        $sincronizada = $ruta -match '\\OneDrive( - [^\\]+)?\\'
        foreach ($raiz in $raicesOneDrive) {
            if ($ruta.StartsWith($raiz, [StringComparison]::OrdinalIgnoreCase)) { $sincronizada = $true }
        }
        $oneDrive[$nombre] = $sincronizada
        if ($sincronizada) { Escribir-Aviso "$nombre está sincronizada con OneDrive: $ruta" }
        else { Escribir-Ok "$nombre NO está en OneDrive: $ruta" }
    }

    Escribir-Titulo 'Resumen del diagnóstico'
    $resumen | Format-Table -AutoSize | Out-Host
    Write-Host "  Espacio libre en C:  $libre GB"
    Write-Host "  VirtualBox:          $(if ($vbox) { $vbox } else { 'no instalado' })"
    Write-Host "  Documentos en OneDrive: $(if ($oneDrive['Documentos']) { 'SÍ' } else { 'no' })"
    Write-Host "  Escritorio en OneDrive: $(if ($oneDrive['Escritorio']) { 'SÍ' } else { 'no' })"
    if ($oneDrive['Documentos'] -or $oneDrive['Escritorio']) {
        Write-Host "  -> Por eso los proyectos irán en $CarpetaProyectos (fuera de OneDrive)."
    }
    $faltan = @($resumen | Where-Object { $_.Estado -eq 'Falta' } | ForEach-Object { $_.Programa })
    if ($faltan.Count -gt 0) {
        Write-Host "  Se instalará (con tu confirmación una a una): $($faltan -join ', ')" -ForegroundColor White
    } else {
        Write-Host '  No falta ningún programa del Paso 2.' -ForegroundColor White
    }
    Write-Host ''
    Esperar-Ok '¿Continuamos con el Paso 2 (instalación)?'
}

# ---------------------------------------------------------------------------
# PASO 2 - Instalación
# ---------------------------------------------------------------------------

function Configurar-Git {
    Actualizar-Path
    if (-not (Version-Git)) {
        Escribir-Aviso 'git no responde todavía; configúralo después de reabrir la terminal (-DesdePaso 2).'
        return
    }
    Write-Host ''
    Write-Host 'Configuración global de Git:'
    $nombreActual = & git config --global user.name 2>$null
    $correoActual = & git config --global user.email 2>$null

    $nombre = (Read-Host "  Tu nombre para user.name$(if ($nombreActual) { " [Enter = $nombreActual]" })").Trim()
    if (-not $nombre) { $nombre = $nombreActual }
    $correo = (Read-Host "  Tu correo para user.email$(if ($correoActual) { " [Enter = $correoActual]" })").Trim()
    if (-not $correo) { $correo = $correoActual }

    if ($nombre) { & git config --global user.name $nombre }
    if ($correo) { & git config --global user.email $correo }
    & git config --global init.defaultBranch main
    & git config --global core.autocrlf true

    Escribir-Ok "user.name          = $(& git config --global user.name)"
    Escribir-Ok "user.email         = $(& git config --global user.email)"
    Escribir-Ok "init.defaultBranch = $(& git config --global init.defaultBranch)"
    Escribir-Ok "core.autocrlf      = $(& git config --global core.autocrlf)"
}

function Instalar-Wsl {
    $wsl = $Programas | Where-Object { $_.Nombre -eq 'WSL 2' }
    if (Esta-Instalado $wsl) {
        Escribir-Ok "WSL ya está instalado ($(Version-Wsl)). Se omite."
        return $true
    }
    Write-Host ''
    if (-not (Confirmar '¿Instalar WSL 2 SIN distribución?  (wsl --install --no-distribution, requiere permisos de administrador)')) {
        Write-Host '  Omitido por ti: WSL 2 (Docker Desktop lo necesita para funcionar).'
        return $true
    }
    if (Es-Admin) {
        & wsl.exe --install --no-distribution
    } else {
        Write-Host '  Se abrirá una ventana de PowerShell como administrador (acepta el aviso de UAC).'
        Write-Host '  Cuando termine, lee el resultado y CIERRA esa ventana para volver aquí.'
        Start-Process powershell.exe -Verb RunAs -Wait -ArgumentList @(
            '-NoExit', '-Command', 'wsl.exe --install --no-distribution'
        )
    }
    Write-Host ''
    Write-Host '  Si apareció un error sobre "--no-distribution", tu WSL es antiguo: ejecuta "wsl --update" como administrador y repite.'
    if (Confirmar '¿El instalador de WSL indicó que hay que REINICIAR el equipo?') {
        Escribir-Titulo 'Reinicio necesario'
        Write-Host '  1. Guarda tu trabajo y reinicia Windows.'
        Write-Host '  2. Abre PowerShell (normal, no hace falta como administrador) en la carpeta de este script.'
        Write-Host '  3. Continúa con:'
        Write-Host "       powershell -ExecutionPolicy Bypass -File .\$NombreScript -DesdePaso 2" -ForegroundColor White
        Write-Host '     Lo que ya está instalado se detecta y se omite; seguirá con Docker Desktop.'
        if (Confirmar '¿Reiniciar ahora?') { Restart-Computer }
        return $false
    }
    [void](Verificar-Programa $wsl 2)
    return $true
}

function Paso2-Instalacion {
    Escribir-Titulo 'PASO 2 - Instalación (solo lo que falte)'

    foreach ($p in $Programas) {
        if ($p.Nombre -eq 'WSL 2') {
            if (-not (Instalar-Wsl)) { exit 0 }   # Reinicio pendiente
            continue
        }

        if (Esta-Instalado $p) {
            Escribir-Ok "$($p.Nombre) ya está instalado ($(& $p.Version)). Se omite."
        } else {
            if ($p.Nombre -eq 'Docker Desktop') {
                Write-Host ''
                Write-Host '  Docker Desktop: el instalador pedirá permisos de administrador. NO se aceptará la licencia'
                Write-Host '  por ti: la aceptas tú la primera vez que abras Docker Desktop.'
            }
            Instalar-ConWinget $p
        }

        if ($p.Nombre -eq 'Git') { Configurar-Git }
    }

    Write-Host ''
    Write-Host '  Docker Desktop: ábrelo desde el menú Inicio, acepta los términos y elige "Use WSL 2" si te lo pregunta.'
    Write-Host '  Si te pide cerrar sesión o reiniciar (para añadirte al grupo docker-users), hazlo y continúa con -DesdePaso 3.'
}

# ---------------------------------------------------------------------------
# PASO 3 - Extensiones de VS Code
# ---------------------------------------------------------------------------

function Paso3-Extensiones {
    Escribir-Titulo 'PASO 3 - Extensiones de VS Code'
    Actualizar-Path
    if (-not (Version-Code)) {
        Escribir-Aviso 'El comando "code" no responde. Cierra y vuelve a abrir PowerShell y continúa con:'
        Write-Host "          powershell -ExecutionPolicy Bypass -File .\$NombreScript -DesdePaso 3" -ForegroundColor White
        return
    }

    $instaladas = @(& code.cmd --list-extensions 2>$null)
    $todas = $false
    foreach ($ext in $Extensiones) {
        if ($instaladas -contains $ext) {
            Escribir-Ok "$ext ya instalada."
            continue
        }
        if (-not $todas) {
            $r = Confirmar-ConTodas "¿Instalar extensión $ext?"
            if ($r -eq 'N') { Write-Host "  Omitida: $ext"; continue }
            if ($r -eq 'T') { $todas = $true }
        }
        & code.cmd --install-extension $ext
        if ($LASTEXITCODE -eq 0) { Escribir-Ok "$ext instalada." } else { Escribir-Error "No se pudo instalar $ext (código $LASTEXITCODE)." }
    }
}

# ---------------------------------------------------------------------------
# PASO 4 - Carpeta de proyectos
# ---------------------------------------------------------------------------

function Paso4-Carpeta {
    Escribir-Titulo "PASO 4 - Carpeta de proyectos ($CarpetaProyectos)"
    if (Test-Path $CarpetaProyectos) {
        Escribir-Ok "$CarpetaProyectos ya existe."
        return
    }
    if (Confirmar "¿Crear $CarpetaProyectos (fuera de OneDrive)?") {
        New-Item -ItemType Directory -Path $CarpetaProyectos -Force | Out-Null
        Escribir-Ok "Creada $CarpetaProyectos"
    } else {
        Write-Host '  Omitido por ti.'
    }
}

# ---------------------------------------------------------------------------
# PASO 5 - Verificación final
# ---------------------------------------------------------------------------

function Docker-Funciona {
    $null = & docker info 2>$null
    return ($LASTEXITCODE -eq 0)
}

function Paso5-Verificacion {
    Escribir-Titulo 'PASO 5 - Verificación final'
    Actualizar-Path

    $docker = $null -ne (Version-Docker)
    if ($docker) {
        while (-not (Docker-Funciona)) {
            Escribir-Aviso 'El motor de Docker no está corriendo.'
            Write-Host '          Abre Docker Desktop, acepta tú los términos y espera a ver "Engine running".'
            $r = (Read-Host '          Pulsa Enter para reintentar o escribe OMITIR para saltar las pruebas de Docker').Trim()
            if ($r -match '^omitir$') { $docker = $false; break }
        }
    } else {
        Escribir-Aviso 'docker no responde; se omiten las pruebas de Docker.'
    }

    if ($docker) {
        if (Confirmar '¿Ejecutar "docker run --rm hello-world"?') {
            & docker run --rm hello-world
            if ($LASTEXITCODE -eq 0) { Escribir-Ok 'hello-world funcionó.' } else { Escribir-Error "hello-world falló (código $LASTEXITCODE)." }
        }
        if (Confirmar '¿Descargar la imagen "postgres:16" (~150 MB de descarga, ~450 MB en disco)?') {
            & docker pull postgres:16
            if ($LASTEXITCODE -eq 0) { Escribir-Ok 'postgres:16 descargada.' } else { Escribir-Error "docker pull falló (código $LASTEXITCODE)." }
        }
    }

    $tabla = @(
        [pscustomobject]@{ Programa = 'Node.js';        Version = (Version-Node) },
        [pscustomobject]@{ Programa = 'npm';            Version = (Version-Npm) },
        [pscustomobject]@{ Programa = 'Git';            Version = (Version-Git) },
        [pscustomobject]@{ Programa = 'Docker';         Version = (Version-Docker) },
        [pscustomobject]@{ Programa = 'WSL';            Version = (Version-Wsl) },
        [pscustomobject]@{ Programa = 'VS Code (code)'; Version = (Version-Code) }
    ) | ForEach-Object {
        if (-not $_.Version) { $_.Version = 'NO RESPONDE (reabre la terminal)' }
        $_
    }

    Escribir-Titulo 'Resultado'
    $tabla | Format-Table -AutoSize | Out-Host
    Write-Host "  Espacio libre que queda en C:  $(Libre-CGB) GB" -ForegroundColor White
    Write-Host "  Carpeta de proyectos:          $CarpetaProyectos $(if (Test-Path $CarpetaProyectos) { '(existe)' } else { '(NO existe)' })"

    Escribir-Titulo 'Cómo liberar espacio de Docker cuando lo necesites'
    Write-Host @'
  Ver qué ocupa Docker:
      docker system df

  Limpieza segura (contenedores parados, redes sin uso, imágenes "dangling" y caché de build):
      docker system prune

  Limpieza más agresiva (además borra TODAS las imágenes que no use ningún contenedor):
      docker system prune -a

  Volúmenes sin usar (¡OJO! aquí viven los datos de PostgreSQL; bórralos solo si no los necesitas):
      docker volume ls
      docker volume prune

  Docker Desktop > Settings > Resources:
    - Advanced: limita CPU, memoria, swap y el tamaño máximo del disco virtual.
    - Disk image location: dónde vive el disco virtual (déjalo en C: por defecto).
  Docker Desktop > Troubleshoot (icono del bicho): "Clean / Purge data" borra TODO y deja Docker como recién instalado.

  Nota: el disco virtual de Docker (un .vhdx) no siempre se encoge solo tras un prune.
  Docker Desktop recupera ese espacio automáticamente al reiniciarse en versiones recientes.
'@
    Write-Host ''
    Write-Host '  Siguiente paso (más adelante): crear el proyecto en C:\Dev\Proyectos\kubo' -ForegroundColor White
}

# ---------------------------------------------------------------------------
# Programa principal
# ---------------------------------------------------------------------------

Write-Host ''
Write-Host 'Instalador del entorno Next.js full-stack (Next.js + Prisma + PostgreSQL en Docker + Tailwind)' -ForegroundColor Cyan
if ($DesdePaso -gt 1) { Write-Host "Continuando desde el Paso $DesdePaso." -ForegroundColor Cyan }

if ($DesdePaso -le 1) { Paso1-Diagnostico }
if ($DesdePaso -le 2) { Paso2-Instalacion }
if ($DesdePaso -le 3) { Paso3-Extensiones }
if ($DesdePaso -le 4) { Paso4-Carpeta }
Paso5-Verificacion
