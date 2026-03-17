#!/usr/bin/env bash
set -euo pipefail

if ! declare -F info >/dev/null 2>&1; then
  DOTFILES_LOG_FILE="${DOTFILES_LOG_FILE:-$HOME/.dotfiles-install.log}"
  touch "$DOTFILES_LOG_FILE" 2>/dev/null || true
  RED="\033[0;31m"; GREEN="\033[0;32m"; YELLOW="\033[0;33m"; CYAN="\033[0;36m"; RESET="\033[0m"
  timestamp() { date +"%Y-%m-%d %H:%M:%S"; }
  _log() { printf "%s %s\n" "$(timestamp)" "$*" >>"$DOTFILES_LOG_FILE"; }
  info() { printf "${CYAN}ℹ %s${RESET}\n" "$*"; _log "[INFO] $*"; }
  success() { printf "${GREEN}✔ %s${RESET}\n" "$*"; _log "[OK] $*"; }
  warn() { printf "${YELLOW}⚠ %s${RESET}\n" "$*"; _log "[WARN] $*"; }
  error() { printf "${RED}✖ %s${RESET}\n" "$*"; _log "[ERR] $*"; }
  step() { printf "${CYAN}→ %s${RESET}\n" "$*"; _log "[STEP] $*"; }
  confirm() {
    local prompt="${1:-¿Continuar?}" ans=""
    read -r -p "$(printf "%b%s [s/N]: %b" "$YELLOW" "$prompt" "$RESET")" ans || true
    [[ "${ans,,}" == "s" || "${ans,,}" == "si" || "${ans,,}" == "sí" ]]
  }
  run_cmd() {
    local desc="$1"; shift
    step "$desc"
    _log "[CMD] $*"
    set +e
    "$@" >>"$DOTFILES_LOG_FILE" 2>&1
    local rc=$?
    set -e
    if [[ $rc -ne 0 ]]; then
      error "Falló: $desc (rc=$rc). Log: $DOTFILES_LOG_FILE"
      if confirm "¿Continuar pese al error?"; then
        warn "Continuando tras error: $desc"
        return 0
      fi
      return "$rc"
    fi
    success "$desc"
  }
fi

install_vscode() {
  info "Este módulo instalará Visual Studio Code desde el repo oficial de Microsoft y extensiones recomendadas."
  info "Log: $DOTFILES_LOG_FILE"
  if ! confirm "¿Instalar VS Code?"; then
    warn "VS Code: cancelado."
    return 0
  fi

  if command -v code >/dev/null 2>&1; then
    success "VS Code ya está instalado: $(code --version 2>/dev/null | head -n 1 || true)"
  else
    run_cmd "Instalar dependencias (wget, gpg)" sudo apt-get update -y
    run_cmd "Instalar dependencias (wget, gpg)" sudo apt-get install -y wget gpg apt-transport-https ca-certificates

    # Add Microsoft repo (idempotent)
    if [[ ! -f /etc/apt/keyrings/packages.microsoft.gpg ]]; then
      run_cmd "Agregar keyring de Microsoft" bash -lc 'wget -qO- https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor | sudo tee /etc/apt/keyrings/packages.microsoft.gpg >/dev/null'
      run_cmd "Ajustar permisos keyring" sudo chmod go+r /etc/apt/keyrings/packages.microsoft.gpg
    else
      success "Keyring de Microsoft ya existe."
    fi

    if [[ ! -f /etc/apt/sources.list.d/vscode.list ]]; then
      run_cmd "Agregar repo de VS Code" bash -lc 'echo "deb [arch=amd64,arm64,armhf signed-by=/etc/apt/keyrings/packages.microsoft.gpg] https://packages.microsoft.com/repos/code stable main" | sudo tee /etc/apt/sources.list.d/vscode.list >/dev/null'
    else
      success "Repo de VS Code ya está configurado."
    fi

    run_cmd "Actualizar apt (repo Microsoft)" sudo apt-get update -y
    run_cmd "Instalar VS Code (code)" sudo apt-get install -y code
  fi

  if ! command -v code >/dev/null 2>&1; then
    error "No se pudo verificar 'code' en PATH."
    return 1
  fi

  info "Instalando extensiones recomendadas (si code CLI está disponible)..."
  local -a exts=(
    "ms-python.python"
    "ms-azuretools.vscode-docker"
    "dbaeumer.vscode-eslint"
    "esbenp.prettier-vscode"
    "ms-kubernetes-tools.vscode-kubernetes-tools"
    "amazonwebservices.aws-toolkit-vscode"
    "eamodio.gitlens"
  )
  local e
  for e in "${exts[@]}"; do
    if code --list-extensions 2>/dev/null | grep -qx "$e"; then
      success "Extensión ya instalada: $e"
    else
      run_cmd "Instalar extensión: $e" code --install-extension "$e"
    fi
  done

  success "VS Code listo."
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  install_vscode
fi

