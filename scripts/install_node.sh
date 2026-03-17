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

ensure_block_in_rc() {
  local rcfile="$1"
  [[ "$rcfile" == ~* ]] && rcfile="${rcfile/#\~/$HOME}"
  [[ -z "$HOME" ]] && export HOME="${HOME:-$(getent passwd "$(whoami)" 2>/dev/null | cut -d: -f6)}"
  local marker_begin="# >>> nvm (dotfiles) >>>"
  mkdir -p "$(dirname -- "$rcfile")" 2>/dev/null || true
  if [[ -f "$rcfile" ]] && grep -Fq "$marker_begin" "$rcfile"; then
    success "Bloque nvm ya existe en $(basename -- "$rcfile")."
    return 0
  fi
  if [[ ! -f "$rcfile" ]]; then
    if ! printf '\n' >>"$rcfile" 2>/dev/null; then
      warn "Se omite $(basename -- "$rcfile") (no existe o no se pudo crear; instala zsh antes si quieres usarlo)."
      return 0
    fi
  fi
  if ! cat >>"$rcfile" <<'EOF'

# >>> nvm (dotfiles) >>>
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"
# <<< nvm (dotfiles) <<<
EOF
  then
    warn "No se pudo escribir en $rcfile; se omite."
    return 0
  fi
  success "Bloque nvm agregado a $(basename -- "$rcfile")."
}

install_node() {
  info "Este módulo instalará nvm v0.39.7 y Node.js LTS."
  info "Log: $DOTFILES_LOG_FILE"
  if ! confirm "¿Instalar Node (nvm + LTS)?"; then
    warn "Node: cancelado."
    return 0
  fi

  run_cmd "Instalar dependencias (curl, ca-certificates)" sudo apt-get update -y
  run_cmd "Instalar dependencias (curl, ca-certificates)" sudo apt-get install -y curl ca-certificates

  if [[ -d "$HOME/.nvm" ]] && command -v node >/dev/null 2>&1; then
    success "Parece que nvm/node ya están instalados: $(node --version 2>/dev/null || true)"
  else
    run_cmd "Instalar nvm v0.39.7" bash -lc 'curl -fsSL https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.7/install.sh | bash'
  fi

  ensure_block_in_rc "$HOME/.zshrc"
  ensure_block_in_rc "$HOME/.bashrc"

  # Load nvm in current session
  export NVM_DIR="$HOME/.nvm"
  # shellcheck disable=SC1090
  [[ -s "$NVM_DIR/nvm.sh" ]] && . "$NVM_DIR/nvm.sh"

  if ! command -v nvm >/dev/null 2>&1; then
    error "nvm no está disponible en esta sesión. Abre una nueva terminal o sourcea tu rc."
    return 1
  fi

  run_cmd "Instalar Node LTS" nvm install --lts
  run_cmd "Definir alias default" nvm alias default node

  success "Node listo: $(node --version 2>/dev/null || true)"
  success "npm listo: $(npm --version 2>/dev/null || true)"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  install_node
fi

