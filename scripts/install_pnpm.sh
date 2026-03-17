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

install_pnpm() {
  info "Este módulo instalará pnpm preferentemente vía corepack."
  info "Log: $DOTFILES_LOG_FILE"
  if ! confirm "¿Instalar pnpm?"; then
    warn "pnpm: cancelado."
    return 0
  fi

  if command -v pnpm >/dev/null 2>&1; then
    success "pnpm ya está instalado: $(pnpm --version 2>/dev/null || true)"
    return 0
  fi

  if command -v corepack >/dev/null 2>&1; then
    run_cmd "Habilitar corepack" corepack enable
    run_cmd "Activar pnpm@latest" corepack prepare pnpm@latest --activate
  else
    warn "corepack no está disponible. Usando script oficial de pnpm."
    run_cmd "Instalar pnpm (script oficial)" bash -lc 'curl -fsSL https://get.pnpm.io/install.sh | sh -'
    warn "Si pnpm no aparece en PATH, abre una nueva terminal o revisa tu shell rc."
  fi

  if command -v pnpm >/dev/null 2>&1; then
    success "pnpm listo: $(pnpm --version 2>/dev/null || true)"
  else
    error "No se pudo verificar pnpm tras instalación."
    return 1
  fi
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  install_pnpm
fi

