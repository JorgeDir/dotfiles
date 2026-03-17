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

get_latest_nosqlbooster_deb_url() {
  # Tries to find the latest Ubuntu .deb link from downloads page.
  local html
  html="$(curl -fsSL https://nosqlbooster.com/downloads 2>/dev/null || true)"
  if [[ -z "$html" ]]; then
    return 1
  fi
  # Heuristic: look for href containing .deb and linux/ubuntu
  printf "%s" "$html" \
    | tr '"' '\n' \
    | grep -E '\.deb$' \
    | grep -E 'NoSQLBooster|nosqlbooster|ubuntu|linux' \
    | head -n 1
}

install_gui_tools() {
  info "Este módulo instalará DBeaver CE (snap) y NoSQLBooster (deb)."
  info "Log: $DOTFILES_LOG_FILE"
  if ! confirm "¿Instalar GUI Tools?"; then
    warn "GUI Tools: cancelado."
    return 0
  fi

  # DBeaver CE via snap
  if command -v snap >/dev/null 2>&1 && snap list 2>/dev/null | awk '{print $1}' | grep -qx "dbeaver-ce"; then
    success "DBeaver CE ya está instalado (snap)."
  else
    run_cmd "Instalar DBeaver CE (snap)" sudo snap install dbeaver-ce
  fi

  # NoSQLBooster via .deb
  if command -v nosqlbooster4mongo >/dev/null 2>&1 || command -v nosqlbooster >/dev/null 2>&1; then
    success "NoSQLBooster ya parece estar instalado."
    return 0
  fi

  info "Detectando URL más reciente de NoSQLBooster (.deb)…"
  local url=""
  url="$(get_latest_nosqlbooster_deb_url || true)"
  if [[ -z "$url" ]]; then
    warn "No se pudo detectar automáticamente la URL del .deb."
    info "Abre la página y descarga manualmente: https://nosqlbooster.com/downloads"
    return 0
  fi

  if [[ "$url" != http* ]]; then
    # If relative, build absolute
    url="https://nosqlbooster.com${url}"
  fi

  local tmp; tmp="$(mktemp -d)"
  local deb="$tmp/nosqlbooster.deb"
  run_cmd "Descargar NoSQLBooster (.deb)" curl -fsSL "$url" -o "$deb"
  run_cmd "Instalar NoSQLBooster (dpkg -i)" sudo dpkg -i "$deb"

  # Fix missing deps if any
  run_cmd "Corregir dependencias (apt-get -f install)" sudo apt-get -f install -y

  rm -rf "$tmp"
  success "GUI Tools listos."
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  install_gui_tools
fi

