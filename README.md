# Dotfiles — Setup de Desarrollo (Ubuntu 22.04/24.04)

## Inicio rápido

**HTTPS** (funciona sin configurar nada):

```bash
git clone https://github.com/JorgeDir/dotfiles.git dotfiles && cd dotfiles && chmod +x install.sh && ./install.sh
```

**SSH** (si ya tienes clave SSH en GitHub):

```bash
git clone git@github.com:JorgeDir/dotfiles.git dotfiles && cd dotfiles && chmod +x install.sh && ./install.sh
```

## Módulos incluidos

| # | Módulo | Qué instala/configura |
|---|--------|------------------------|
| 1 | Shell | zsh + oh-my-zsh + plugins + `config/.zshrc` |
| 2 | Git | git + wizard para `~/.gitconfig` + SSH key opcional |
| 3 | AWS CLI | AWS CLI v2 + opción de abrir wizard AWS SSO |
| 4 | Docker | Docker Engine + Compose v2 + grupo `docker` + systemd |
| 5 | Python | pyenv + Python 3.11.9 + 3.13.12 (global 3.13.12) |
| 6 | Node | nvm v0.39.7 + Node LTS + alias default |
| 7 | pnpm | pnpm vía corepack (fallback script oficial) |
| 8 | VS Code | VS Code (repo MS) + extensiones recomendadas |
| 9 | GUI Tools | DBeaver CE (snap o apt) + NoSQLBooster (AppImage) |

## Configurar AWS SSO (wizard interactivo)

El wizard administra `~/.aws/config` y se abre desde el menú principal con la opción **`c`** (Configurar AWS SSO).

### Cómo entrar al wizard

1. Ejecuta `./install.sh`.
2. En el menú, pulsa **`c`** y Enter.
3. Confirma "¿Abrir configurador AWS SSO?" con `s` y Enter.
4. Si ya tienes `~/.aws/config`, te avisará y te ofrecerá hacer un **backup** antes de seguir (recomendado: `s`).

### Menú del configurador SSO

| Opción | Qué hace |
|--------|----------|
| **1** | **Ver perfiles actuales** — Muestra el contenido de `~/.aws/config` (truncado si es muy largo). |
| **2** | **Agregar nuevo perfil SSO** — Te pide nombre de perfil, Account ID, rol IAM, SSO Start URL, región, etc. y **añade** el perfil al final del archivo (no borra nada). Puedes reutilizar una `sso-session` existente o crear una nueva. |
| **3** | **Eliminar perfil** — Lista los perfiles, eliges uno por número y lo elimina del archivo (hace backup antes). |
| **4** | **Editar perfil existente** — Eliges un perfil y se abre `~/.aws/config` en tu editor (`$EDITOR` o nano). Editas a mano y guardas. |
| **5** | **Importar config completo desde template** — Sustituye todo `~/.aws/config` por el contenido del template del repo. El template tiene placeholders; el wizard te pide los **nombres de perfil** (y opcionalmente aliases, ej. `developer, jorge-dev`) y genera el archivo listo. Siempre hace backup antes. |
| **6** | **Hacer backup del config actual** — Copia `~/.aws/config` a `~/.aws/config.backup.YYYYMMDDHHMMSS`. |
| **7** | **Probar login de un perfil** — Eliges un perfil de la lista; ejecuta `aws sso login --profile <nombre>` y luego `aws sts get-caller-identity --profile <nombre>` para comprobar que el login funciona. |
| **q** | **Volver al menú principal** — Sale del wizard y vuelves al menú de dotfiles. |

### Flujo típico

- **Primera vez (sin config):** Opción **5** (Importar desde template), introduces los nombres de perfil que quieras y, si quieres, aliases. Luego opción **7** para probar un perfil.
- **Ya tienes config y quieres otro perfil:** Opción **2** (Agregar nuevo perfil SSO), rellenas los datos y confirmas.
- **Revisar o cambiar algo:** Opción **1** para ver, opción **4** para editar con tu editor, u opción **6** para backup y luego editar a mano.

### Notas

- El template (`config/aws/config.template`) usa placeholders `{{...}}` solo para **nombres de perfil**; la URL SSO y los roles van fijos en el template.
- Si en la opción 5 pones **aliases** (ej. `developer, jorge-dev`), podrás usar tanto `aws sso login --profile developer` como `aws sso login --profile jorge-dev`.

## Aliases disponibles (más útiles)

| Categoría | Alias/Función | Descripción |
|----------|---------------|-------------|
| AWS | `aws-login <perfil>` | Login SSO usando el nombre que elijas |
| AWS | `aws-use <perfil>` | Cambia `AWS_PROFILE` (genérico) |
| AWS | `aws-login-dev`, `aws-login-qa`, `aws-login-uat`, `aws-login-prod` | Aliases de ejemplo (ajusta a tus nombres) |
| AWS | `use-dev`, `use-qa`, `use-prod` | Aliases de ejemplo para `AWS_PROFILE` |
| AWS | `aws-who` | Muestra identidad del perfil activo |
| kubectl | `k`, `kgp`, `kgs`, `kctx`, `kuse`, `klogs` | Atajos comunes |
| EKS | `eks-connect <cluster> [region]` | `aws eks update-kubeconfig` |
| Docker | `d`, `dc`, `dps`, `dclean`, `dlogs` | Atajos Docker/Compose |
| Git | `gs`, `gp`, `gpush`, `gc`, `gco`, `gb`, `glog` | Atajos Git |
| General | `ll`, `..`, `...`, `ports`, `myip` | Utilidades generales |
| Python | `py`, `venv`, `activate`, `pyv`, `pylocal` | Atajos Python/venv |
| pnpm | `pn`, `pnd`, `pnb` | Atajos pnpm |

## Después de instalar

- Abre una nueva terminal (para cargar `pyenv`/`nvm`/`pnpm` en PATH).
- Si instalaste Docker y te agregó al grupo `docker`, **cierra sesión y vuelve a entrar**.
- Verifica rápido:
  - `git --version`
  - `aws --version`
  - `docker --version` y `docker compose version`
  - `python --version` (debería ser 3.13.12)
  - `node --version`
  - `pnpm --version`

## Instalar DBeaver y NoSQLBooster desde la CLI

Si el módulo GUI Tools no los instaló, puedes hacerlo manualmente:

### DBeaver CE

**Opción 1 — Snap:**
```bash
sudo snap install dbeaver-ce
```

**Opción 2 — APT (PPA):**
```bash
sudo add-apt-repository -y ppa:serge-rider/dbeaver-ce
sudo apt-get update
sudo apt-get install -y dbeaver-ce
```

Comprobar: `dbeaver &`

### NoSQLBooster (MongoDB)

Requiere FUSE (libfuse2). Luego descarga el AppImage y ejecútalo:

```bash
# Dependencia en Ubuntu 22.04+
sudo apt-get install -y libfuse2

# Descargar AppImage (versión 10.1.4)
mkdir -p ~/.local/share/nosqlbooster
curl -fsSL https://s3.nosqlbooster.com/download/releasesv10/nosqlbooster4mongo-10.1.4.AppImage -o ~/.local/share/nosqlbooster/nosqlbooster4mongo.AppImage
chmod +x ~/.local/share/nosqlbooster/nosqlbooster4mongo.AppImage

# Ejecutar (o añadir ~/.local/bin al PATH y enlazar)
~/.local/share/nosqlbooster/nosqlbooster4mongo.AppImage
```

Opcional: enlace en PATH y entrada en el menú de aplicaciones:
```bash
mkdir -p ~/.local/bin
ln -sf ~/.local/share/nosqlbooster/nosqlbooster4mongo.AppImage ~/.local/bin/nosqlbooster4mongo

# Para que aparezca en el menú de aplicaciones
mkdir -p ~/.local/share/applications
cat > ~/.local/share/applications/nosqlbooster4mongo.desktop << EOF
[Desktop Entry]
Name=NoSQLBooster for MongoDB
Comment=GUI client for MongoDB
Exec=$HOME/.local/share/nosqlbooster/nosqlbooster4mongo.AppImage
Icon=database
Type=Application
Categories=Development;Database;
StartupNotify=true
EOF
```
Tras crear el `.desktop`, si no aparece en el menú al momento, cierra sesión y vuelve a entrar o ejecuta: `update-desktop-database ~/.local/share/applications` (si está disponible).

## Logs

Todo se registra en `~/.dotfiles-install.log`.

