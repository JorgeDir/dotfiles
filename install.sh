#!/usr/bin/env bash
set -euo pipefail

# =========================
# DOTFILES - Installer
# Ubuntu 22.04+ / 24.04+
# =========================

export DOTFILES_DIR
# Ruta canónica del repo (evita duplicados tipo .../dotfiles/dotfiles en mensajes)
DOTFILES_DIR="$(cd -P -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"

export DOTFILES_LOG_FILE="${DOTFILES_LOG_FILE:-$HOME/.dotfiles-install.log}"
touch "$DOTFILES_LOG_FILE" 2>/dev/null || true

# Colors
RED="\033[0;31m"
GREEN="\033[0;32m"
YELLOW="\033[0;33m"
CYAN="\033[0;36m"
RESET="\033[0m"
GRAY="\033[0;90m"

# Helpers (shared with sourced scripts)
timestamp() { date +"%Y-%m-%d %H:%M:%S"; }
_log() { printf "%s %s\n" "$(timestamp)" "$*" >>"$DOTFILES_LOG_FILE"; }

info() { printf "${CYAN}ℹ %s${RESET}\n" "$*"; _log "[INFO] $*"; }
success() { printf "${GREEN}✔ %s${RESET}\n" "$*"; _log "[OK] $*"; }
warn() { printf "${YELLOW}⚠ %s${RESET}\n" "$*"; _log "[WARN] $*"; }
error() { printf "${RED}✖ %s${RESET}\n" "$*"; _log "[ERR] $*"; }
step() { printf "${CYAN}→ %s${RESET}\n" "$*"; _log "[STEP] $*"; }

confirm() {
  local prompt="${1:-¿Continuar?}"
  local ans=""
  read -r -p "$(printf "%b%s [s/N]: %b" "$YELLOW" "$prompt" "$RESET")" ans || true
  [[ "${ans,,}" == "s" || "${ans,,}" == "si" || "${ans,,}" == "sí" ]]
}

die() { error "$*"; exit 1; }

ensure_dir() { mkdir -p "$1"; }

ensure_local_bin_on_path() {
  # Prefer user-level PATH without sudo: ~/.local/bin
  ensure_dir "$HOME/.local/bin"
  case ":$PATH:" in
    *":$HOME/.local/bin:"*) ;;
    *) export PATH="$HOME/.local/bin:$PATH" ;;
  esac

  local line='export PATH="$HOME/.local/bin:$PATH"'
  local marker_begin="# >>> dotfiles path (dotfiles) >>>"
  local marker_end="# <<< dotfiles path (dotfiles) <<<"

  local f
  for f in "$HOME/.bashrc" "$HOME/.zshrc"; do
    [[ -f "$f" ]] || continue
    if grep -Fq "$marker_begin" "$f"; then
      continue
    fi
    cat >>"$f" <<EOF

$marker_begin
$line
$marker_end
EOF
  done
}

backup_file() {
  local f="$1"
  [[ -f "$f" ]] || return 0
  local ts
  ts="$(date +%Y%m%d%H%M%S)"
  cp -f "$f" "$f.backup.$ts"
  success "Backup creado: $f.backup.$ts"
}

has_cmd() { command -v "$1" >/dev/null 2>&1; }

run_cmd() {
  # Runs command, logs stdout/stderr, and on failure asks if continue.
  local desc="$1"; shift
  step "$desc"
  _log "[CMD] $*"
  set +e
  "$@" >>"$DOTFILES_LOG_FILE" 2>&1
  local rc=$?
  set -e
  if [[ $rc -ne 0 ]]; then
    error "Falló: $desc (rc=$rc). Revisa el log: $DOTFILES_LOG_FILE"
    if confirm "¿Continuar pese al error?"; then
      warn "Continuando tras error: $desc"
      return 0
    fi
    return "$rc"
  fi
  success "$desc"
  return 0
}

require_ubuntu() {
  if [[ ! -f /etc/os-release ]]; then
    die "No se detectó /etc/os-release (no es Ubuntu?)."
  fi
  # shellcheck disable=SC1091
  source /etc/os-release
  if [[ "${ID:-}" != "ubuntu" ]]; then
    die "Este instalador está diseñado para Ubuntu (ID=${ID:-desconocido})."
  fi
  local v="${VERSION_ID:-}"
  if [[ "$v" != "22.04" && "$v" != "24.04" ]]; then
    warn "Ubuntu ${v:-desconocido} no está en la lista (22.04/24.04). Se intentará continuar."
  fi
}

banner() {
  clear || true
  cat <<'EOF'
  ____   ___ _____ _____ ___ _     _____ ____  
 |  _ \ / _ \_   _|  ___|_ _| |   | ____/ ___| 
 | | | | | | || | | |_   | || |   |  _| \___ \ 
 | |_| | |_| || | |  _|  | || |___| |___ ___) |
 |____/ \___/ |_| |_|   |___|_____|_____|____/ 
EOF
  printf "\n"
}

source_script() {
  local p="$DOTFILES_DIR/$1"
  [[ -f "$p" ]] || die "No existe el script: $1"
  # shellcheck disable=SC1090
  source "$p"
}

module_ok_icon() { printf "%b✔%b" "$GREEN" "$RESET"; }
module_no_icon() { printf "%b○%b" "$GRAY" "$RESET"; }

is_shell_installed() {
  [[ -f "$HOME/.zshrc" ]] && has_cmd zsh
}
is_git_installed() { has_cmd git; }
is_aws_installed() { has_cmd aws; }
is_docker_installed() { has_cmd docker && docker --version >/dev/null 2>&1; }
is_python_installed() { [[ -d "$HOME/.pyenv" ]] && has_cmd pyenv; }
is_node_installed() { [[ -d "$HOME/.nvm" ]] && has_cmd node; }
is_pnpm_installed() { has_cmd pnpm; }
is_vscode_installed() { has_cmd code; }
is_gui_tools_installed() {
  local ok=0
  if has_cmd snap && snap list 2>/dev/null | awk '{print $1}' | grep -qx "dbeaver-ce"; then ok=$((ok+1)); fi
  if has_cmd nosqlbooster4mongo || has_cmd nosqlbooster; then ok=$((ok+1)); fi
  [[ $ok -ge 1 ]]
}

status_line() {
  local name="$1" installed_fn="$2"
  if "$installed_fn"; then
    printf " %s %s\n" "$(module_ok_icon)" "$name"
  else
    printf " %s %s\n" "$(module_no_icon)" "$name"
  fi
}

print_status() {
  printf "\n${CYAN}Estado del ambiente${RESET}\n"
  printf "Log: %s\n\n" "$DOTFILES_LOG_FILE"
  status_line "Shell (zsh + oh-my-zsh)" is_shell_installed
  status_line "Git" is_git_installed
  status_line "AWS CLI" is_aws_installed
  status_line "Docker" is_docker_installed
  status_line "Python (pyenv)" is_python_installed
  status_line "Node (nvm)" is_node_installed
  status_line "pnpm" is_pnpm_installed
  status_line "VS Code" is_vscode_installed
  status_line "GUI Tools (DBeaver/NoSQLBooster)" is_gui_tools_installed
  printf "\n"
}

install_shell() {
  info "Este módulo instalará zsh + oh-my-zsh + plugins y aplicará tu .zshrc."
  if ! confirm "¿Instalar/Configurar Shell?"; then
    warn "Shell: cancelado por el usuario."
    return 0
  fi

run_cmd "Actualizar apt (puede tardar)" sudo apt-get update -y
run_cmd "Instalar dependencias base (zsh, curl, git)" sudo apt-get install -y zsh curl git ca-certificates

if [[ -d "$HOME/.oh-my-zsh" ]]; then
  success "oh-my-zsh ya está instalado."
else
  # Non-interactive install of oh-my-zsh
  run_cmd "Instalar oh-my-zsh" bash -lc 'RUNZSH=no CHSH=no KEEP_ZSHRC=yes sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"'
fi

ensure_dir "$HOME/.oh-my-zsh/custom/plugins"
if [[ -d "$HOME/.oh-my-zsh/custom/plugins/zsh-autosuggestions" ]]; then
  success "Plugin zsh-autosuggestions ya existe."
else
  run_cmd "Instalar zsh-autosuggestions" git clone --depth=1 https://github.com/zsh-users/zsh-autosuggestions "$HOME/.oh-my-zsh/custom/plugins/zsh-autosuggestions"
fi
if [[ -d "$HOME/.oh-my-zsh/custom/plugins/zsh-syntax-highlighting" ]]; then
  success "Plugin zsh-syntax-highlighting ya existe."
else
  run_cmd "Instalar zsh-syntax-highlighting" git clone --depth=1 https://github.com/zsh-users/zsh-syntax-highlighting "$HOME/.oh-my-zsh/custom/plugins/zsh-syntax-highlighting"
fi

if [[ -f "$DOTFILES_DIR/config/.zshrc" ]]; then
  backup_file "$HOME/.zshrc"
  run_cmd "Aplicar .zshrc desde repo" cp -f "$DOTFILES_DIR/config/.zshrc" "$HOME/.zshrc"
else
  warn "No existe $DOTFILES_DIR/config/.zshrc (se omitió)."
fi

if [[ "${SHELL:-}" != "$(command -v zsh)" ]]; then
  warn "Tu shell actual no es zsh. Se intentará cambiar con chsh."
  if confirm "¿Cambiar tu shell por defecto a zsh (recomendado)?"; then
    local zsh_path
    zsh_path="$(command -v zsh)"
    # chsh exige que el shell esté en /etc/shells
    if [[ -n "$zsh_path" && -x "$zsh_path" ]]; then
      if ! grep -Fxq "$zsh_path" /etc/shells 2>/dev/null; then
        step "Añadir zsh a /etc/shells"
        echo "$zsh_path" | sudo tee -a /etc/shells >>"$DOTFILES_LOG_FILE" 2>&1 && success "zsh añadido a /etc/shells" || warn "No se pudo añadir zsh a /etc/shells (chsh puede fallar)."
      fi
    fi
    step "Cambiar shell por defecto (chsh)"
    if chsh -s "${zsh_path:-$(command -v zsh)}" >>"$DOTFILES_LOG_FILE" 2>&1; then
      success "Shell por defecto cambiado a zsh."
      warn "Cierra sesión y vuelve a entrar para aplicar el cambio."
    else
      warn "chsh falló (revisa $DOTFILES_LOG_FILE). Puedes cambiarlo después con: chsh -s $(command -v zsh)"
      warn "Cierra sesión y vuelve a entrar después de ejecutar chsh."
    fi
  fi
fi
}

install_git_module() { source_script "scripts/install_git.sh"; install_git; }
install_awscli_module() { source_script "scripts/install_awscli.sh"; install_awscli; }
install_docker_module() { source_script "scripts/install_docker.sh"; install_docker; }
install_python_module() { source_script "scripts/install_python.sh"; install_python; }
install_node_module() { source_script "scripts/install_node.sh"; install_node; }
install_pnpm_module() { source_script "scripts/install_pnpm.sh"; install_pnpm; }
install_vscode_module() { source_script "scripts/install_vscode.sh"; install_vscode; }
install_gui_tools_module() { source_script "scripts/install_gui_tools.sh"; install_gui_tools; }
configure_aws_sso_module() { source_script "scripts/configure_aws_sso.sh"; configure_aws_sso; }

run_all() {
  info "Se instalarán TODOS los módulos. Cada uno pedirá confirmación."
  if ! confirm "¿Iniciar instalación completa?"; then
    warn "Instalar TODO: cancelado."
    return 0
  fi

  local -a ok=() fail=()

  install_shell && ok+=("Shell") || fail+=("Shell")
  install_git_module && ok+=("Git") || fail+=("Git")
  install_awscli_module && ok+=("AWS CLI") || fail+=("AWS CLI")
  install_docker_module && ok+=("Docker") || fail+=("Docker")
  install_python_module && ok+=("Python") || fail+=("Python")
  install_node_module && ok+=("Node") || fail+=("Node")
  install_pnpm_module && ok+=("pnpm") || fail+=("pnpm")
  install_vscode_module && ok+=("VS Code") || fail+=("VS Code")
  install_gui_tools_module && ok+=("GUI Tools") || fail+=("GUI Tools")

  printf "\n${CYAN}Resumen instalación completa${RESET}\n"
  if [[ ${#ok[@]} -gt 0 ]]; then
    printf "${GREEN}Instalado:${RESET}\n"
    for m in "${ok[@]}"; do printf " - %s\n" "$m"; done
  fi
  if [[ ${#fail[@]} -gt 0 ]]; then
    printf "${RED}Falló:${RESET}\n"
    for m in "${fail[@]}"; do printf " - %s\n" "$m"; done
    warn "Revisa el log: $DOTFILES_LOG_FILE"
  else
    success "Todo quedó instalado correctamente."
  fi
  printf "\n"
}

menu() {
  require_ubuntu
  ensure_dir "$DOTFILES_DIR/scripts"
  ensure_dir "$DOTFILES_DIR/config/aws"
  ensure_local_bin_on_path

  while true; do
    banner

    printf "%s 1. Shell          zsh + oh-my-zsh + plugins\n" "$([[ $(is_shell_installed && echo y || echo n) == y ]] && module_ok_icon || module_no_icon)"
    printf "%s 2. Git            git + gitconfig global\n" "$([[ $(is_git_installed && echo y || echo n) == y ]] && module_ok_icon || module_no_icon)"
    printf "%s 3. AWS CLI        v2 + perfiles SSO\n" "$([[ $(is_aws_installed && echo y || echo n) == y ]] && module_ok_icon || module_no_icon)"
    printf "%s 4. Docker         Engine v2 + Compose\n" "$([[ $(is_docker_installed && echo y || echo n) == y ]] && module_ok_icon || module_no_icon)"
    printf "%s 5. Python         pyenv + 3.11 + 3.13\n" "$([[ $(is_python_installed && echo y || echo n) == y ]] && module_ok_icon || module_no_icon)"
    printf "%s 6. Node           nvm + LTS\n" "$([[ $(is_node_installed && echo y || echo n) == y ]] && module_ok_icon || module_no_icon)"
    printf "%s 7. pnpm           gestor de paquetes rápido\n" "$([[ $(is_pnpm_installed && echo y || echo n) == y ]] && module_ok_icon || module_no_icon)"
    printf "%s 8. VS Code        Visual Studio Code\n" "$([[ $(is_vscode_installed && echo y || echo n) == y ]] && module_ok_icon || module_no_icon)"
    printf "%s 9. GUI Tools      DBeaver CE + NoSQLBooster\n" "$([[ $(is_gui_tools_installed && echo y || echo n) == y ]] && module_ok_icon || module_no_icon)"
    printf "──────────────────────────────────────────\n"
    printf " a. Instalar TODO\n"
    printf " c. Configurar AWS SSO (interactivo)\n"
    printf " s. Ver estado del ambiente\n"
    printf " q. Salir\n\n"

    local choice=""
    read -r -p "$(printf "%bElige una opción:%b " "$CYAN" "$RESET")" choice || true
    case "${choice,,}" in
      1) install_shell ;;
      2) install_git_module ;;
      3) install_awscli_module ;;
      4) install_docker_module ;;
      5) install_python_module ;;
      6) install_node_module ;;
      7) install_pnpm_module ;;
      8) install_vscode_module ;;
      9) install_gui_tools_module ;;
      a) run_all ;;
      c) configure_aws_sso_module ;;
      s) print_status; read -r -p "Enter para volver al menú..." _ || true ;;
      q) info "Saliendo."; return 0 ;;
      *) warn "Opción inválida: $choice"; sleep 1 ;;
    esac
  done
}

menu
