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

install_docker() {
  info "Este módulo instalará Docker Engine (script oficial) + Docker Compose v2 (plugin)."
  info "También agregará tu usuario al grupo 'docker' y activará el servicio."
  info "Log: $DOTFILES_LOG_FILE"
  if ! confirm "¿Instalar Docker?"; then
    warn "Docker: cancelado."
    return 0
  fi

  if command -v docker >/dev/null 2>&1; then
    success "Docker ya está instalado: $(docker --version 2>/dev/null || true)"
  else
    run_cmd "Instalar dependencias (curl, ca-certificates)" sudo apt-get update -y
    run_cmd "Instalar dependencias (curl, ca-certificates)" sudo apt-get install -y curl ca-certificates
    run_cmd "Instalar Docker (get.docker.com)" bash -lc 'curl -fsSL https://get.docker.com | sh'
  fi

  # Compose v2 plugin (package is available on Ubuntu via Docker repo after install script)
  if docker compose version >/dev/null 2>&1; then
    success "Docker Compose v2 ya está disponible: $(docker compose version 2>/dev/null | head -n 1 || true)"
  else
    run_cmd "Instalar plugin docker-compose (v2)" sudo apt-get install -y docker-compose-plugin
  fi

  if getent group docker >/dev/null 2>&1; then
    if id -nG "$USER" | tr ' ' '\n' | grep -qx docker; then
      success "El usuario '$USER' ya pertenece al grupo docker."
    else
      run_cmd "Agregar usuario '$USER' al grupo docker" sudo usermod -aG docker "$USER"
      warn "Necesitas cerrar sesión y volver a entrar para que el grupo docker aplique."
    fi
  else
    warn "No existe el grupo docker (inesperado)."
  fi

  if command -v systemctl >/dev/null 2>&1; then
    run_cmd "Habilitar servicio docker" sudo systemctl enable docker
    run_cmd "Iniciar servicio docker" sudo systemctl start docker
  else
    warn "systemctl no está disponible; se omitió enable/start."
  fi

  success "Docker listo. Prueba: docker run --rm hello-world"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  install_docker
fi

