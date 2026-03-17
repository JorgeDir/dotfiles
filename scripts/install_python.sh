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
  local marker_begin="# >>> pyenv (dotfiles) >>>"
  local parent_dir
  parent_dir="$(dirname -- "$rcfile")"
  mkdir -p "$parent_dir" 2>/dev/null || true

  if [[ -f "$rcfile" ]] && grep -Fq "$marker_begin" "$rcfile"; then
    success "Bloque pyenv ya existe en $(basename -- "$rcfile")."
    return 0
  fi

  if [[ ! -f "$rcfile" ]]; then
    if ! printf '\n' >>"$rcfile" 2>/dev/null; then
      warn "Se omite $(basename -- "$rcfile") (no existe o no se pudo crear; instala zsh antes si quieres usarlo)."
      return 0
    fi
  fi

  if ! cat >>"$rcfile" <<'EOF'

# >>> pyenv (dotfiles) >>>
export PYENV_ROOT="$HOME/.pyenv"
command -v pyenv >/dev/null 2>&1 && export PATH="$PYENV_ROOT/bin:$PATH"
command -v pyenv >/dev/null 2>&1 && eval "$(pyenv init -)"
# <<< pyenv (dotfiles) <<<
EOF
  then
    warn "No se pudo escribir en $rcfile; se omite."
    return 0
  fi
  success "Bloque pyenv agregado a $(basename -- "$rcfile")."
}

install_python() {
  info "Este módulo instalará pyenv y Python 3.11.9 + 3.13.12 (global 3.13.12)."
  info "Log: $DOTFILES_LOG_FILE"
  if ! confirm "¿Instalar Python vía pyenv?"; then
    warn "Python: cancelado."
    return 0
  fi

  run_cmd "Instalar dependencias de build para Python" sudo apt-get update -y
  run_cmd "Instalar dependencias de build para Python" sudo apt-get install -y \
    build-essential libssl-dev zlib1g-dev libbz2-dev libreadline-dev libsqlite3-dev \
    libncursesw5-dev xz-utils tk-dev libxml2-dev libxmlsec1-dev libffi-dev liblzma-dev \
    curl ca-certificates git

  if [[ -d "$HOME/.pyenv" ]] && command -v pyenv >/dev/null 2>&1; then
    success "pyenv ya está instalado."
  else
    # El instalador de pyenv.run se niega a continuar si ~/.pyenv ya existe (ej. instalación previa rota).
    if [[ -d "$HOME/.pyenv" ]]; then
      warn "Existe ~/.pyenv pero pyenv no está disponible. Se eliminará para reinstalar."
      if confirm "¿Eliminar ~/.pyenv y reinstalar?"; then
        run_cmd "Eliminar ~/.pyenv previo" rm -rf "$HOME/.pyenv"
      else
        error "Instalación cancelada. Elimina manualmente: rm -rf ~/.pyenv"
        return 1
      fi
    fi
    run_cmd "Instalar pyenv (pyenv.run)" bash -c 'curl -fsSL https://pyenv.run | bash'
  fi

  ensure_block_in_rc "$HOME/.zshrc"
  ensure_block_in_rc "$HOME/.bashrc"

  # Load pyenv in current shell (this script may be sourced)
  export PYENV_ROOT="$HOME/.pyenv"
  export PATH="$PYENV_ROOT/bin:$PATH"
  if command -v pyenv >/dev/null 2>&1; then
    # shellcheck disable=SC1090
    eval "$(pyenv init -)" || true
  fi

  # Make it available from "anywhere" in user PATH (no sudo)
  mkdir -p "$HOME/.local/bin" 2>/dev/null || true
  if [[ -x "$HOME/.pyenv/bin/pyenv" ]]; then
    ln -sf "$HOME/.pyenv/bin/pyenv" "$HOME/.local/bin/pyenv" 2>/dev/null || true
  fi

  if ! command -v pyenv >/dev/null 2>&1; then
    error "pyenv no está disponible en esta sesión. Abre una nueva terminal o 'source ~/.bashrc'."
    return 1
  fi

  local py311="3.11.9"
  local py312="3.13.12"

  if pyenv versions --bare | grep -qx "$py311"; then
    success "Python $py311 ya está instalado en pyenv."
  else
    run_cmd "Instalar Python $py311 (pyenv)" pyenv install "$py311"
  fi

  if pyenv versions --bare | grep -qx "$py312"; then
    success "Python $py312 ya está instalado en pyenv."
  else
    run_cmd "Instalar Python $py312 (pyenv)" pyenv install "$py312"
  fi

  run_cmd "Configurar pyenv global = $py312" pyenv global "$py312"
  success "Python listo. Verifica: python --version"
  info "También tienes disponible: pyenv local $py311 (por proyecto)"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  install_python
fi

