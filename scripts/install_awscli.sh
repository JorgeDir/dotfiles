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

DOTFILES_DIR="${DOTFILES_DIR:-$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)}"

install_awscli() {
  info "Este módulo instalará AWS CLI v2 y opcionalmente configurará AWS SSO."
  info "Log: $DOTFILES_LOG_FILE"
  if ! confirm "¿Instalar AWS CLI v2?"; then
    warn "AWS CLI: cancelado."
    return 0
  fi

  if command -v aws >/dev/null 2>&1; then
    success "AWS CLI ya está instalado: $(aws --version 2>/dev/null || true)"
  else
    run_cmd "Instalar dependencias (curl, unzip)" sudo apt-get update -y
    run_cmd "Instalar dependencias (curl, unzip)" sudo apt-get install -y curl unzip ca-certificates

    local tmp
    tmp="$(mktemp -d)"
    local zip="$tmp/awscliv2.zip"
    run_cmd "Descargar AWS CLI v2" curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "$zip"
    run_cmd "Descomprimir AWS CLI v2" unzip -q "$zip" -d "$tmp"
    run_cmd "Instalar AWS CLI v2 (sudo ./aws/install)" sudo "$tmp/aws/install" --update
    rm -rf "$tmp"

    if command -v aws >/dev/null 2>&1; then
      success "AWS CLI instalado: $(aws --version 2>/dev/null || true)"
    else
      error "No se pudo verificar 'aws' en PATH tras instalación."
      return 1
    fi
  fi

  if confirm "¿Quieres configurar AWS SSO ahora (wizard interactivo)?"; then
    # shellcheck disable=SC1090
    source "$DOTFILES_DIR/scripts/configure_aws_sso.sh"
    configure_aws_sso
  else
    info "Puedes correrlo luego con: ./install.sh -> opción 'c'"
  fi
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  install_awscli
fi

