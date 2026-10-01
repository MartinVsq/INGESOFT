# Entorno de desarrollo en Windows (Next.js full-stack)

`setup-entorno-windows.ps1` prepara un PC con Windows para el proyecto
(Next.js App Router + Route Handlers, Prisma, PostgreSQL en Docker, Tailwind).
Pide confirmación antes de cada instalación y usa las rutas por defecto de cada programa.

| Paso | Qué hace |
|------|----------|
| 1 | Diagnóstico: espacio en C: (mínimo 25 GB libres), qué hay instalado (`winget list` / `where.exe`), VirtualBox, OneDrive en Documentos/Escritorio. Espera tu `OK`. |
| 2 | Instala solo lo que falte: VS Code, Node.js LTS, Git (+ `user.name`, `user.email`, `init.defaultBranch main`, `core.autocrlf true`), WSL 2 sin distribución, Docker Desktop. Verifica cada uno con `--version`. |
| 3 | Extensiones de VS Code (Prisma, ESLint, Prettier, Tailwind, PostgreSQL, Docker, REST Client, GitLens, Error Lens). |
| 4 | Crea `C:\Dev\Proyectos` (fuera de OneDrive). |
| 5 | Versiones, `docker run --rm hello-world`, `docker pull postgres:16`, tabla final con espacio libre y cómo limpiar Docker. |

## Cómo ejecutarlo

1. Descarga `setup-entorno-windows.ps1` desde GitHub (botón **Download raw file**) a tu carpeta Descargas.
2. Abre **PowerShell** (normal, no hace falta como administrador; cuando algo lo necesite saldrá el aviso de UAC).
3. Ejecuta:

   ```powershell
   cd $HOME\Downloads
   powershell -ExecutionPolicy Bypass -File .\setup-entorno-windows.ps1
   ```

### Continuar después de un reinicio o de reabrir la terminal

El script es re-ejecutable: lo que ya está instalado se detecta y se omite. Para saltar a un paso:

```powershell
powershell -ExecutionPolicy Bypass -File .\setup-entorno-windows.ps1 -DesdePaso 2
```

- Tras instalar WSL, si pide reiniciar: reinicia y continúa con `-DesdePaso 2`.
- Si `code`, `node`, `git` o `docker` "no se reconocen": cierra y abre PowerShell (refresca el PATH) y continúa desde el paso indicado.
- Si Docker Desktop pide cerrar sesión (grupo `docker-users`): hazlo y continúa con `-DesdePaso 3`.

## Licencias

El script **no** usa `--accept-package-agreements`: las licencias de cada programa (en particular la
de Docker Desktop, que se acepta al abrirlo por primera vez) las aceptas tú.
Sí pasa `--accept-source-agreements`, que solo acepta los términos del catálogo de winget.

## Consejo: npm en PowerShell

Si después `npm`/`npx` fallan con "la ejecución de scripts está deshabilitada", ejecuta una vez:

```powershell
Set-ExecutionPolicy -Scope CurrentUser RemoteSigned
```
