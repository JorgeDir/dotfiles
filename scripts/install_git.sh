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
  backup_file() {
    local f="$1"
    [[ -f "$f" ]] || return 0
    local ts; ts="$(date +%Y%m%d%H%M%S)"
    cp -f "$f" "$f.backup.$ts"
    success "Backup creado: $f.backup.$ts"
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

prompt_default() {
  local label="$1" default="$2" outvar="$3"
  local val=""
  read -r -p "$(printf "%s [%s]: " "$label" "$default")" val || true
  if [[ -z "$val" ]]; then val="$default"; fi
  printf -v "$outvar" "%s" "$val"
}

install_git() {
  info "Este módulo instalará Git y configurará ~/.gitconfig con un wizard."
  info "Log: $DOTFILES_LOG_FILE"
  if ! confirm "¿Instalar/Configurar Git?"; then
    warn "Git: cancelado."
    return 0
  fi

  if command -v git >/dev/null 2>&1; then
    success "Git ya está instalado: $(git --version 2>/dev/null || true)"
  else
    run_cmd "Instalar git" sudo apt-get update -y
    run_cmd "Instalar git" sudo apt-get install -y git
  fi

  local name="Jorge Luis Dircio"
  local email="jorge@example.com"
  local editor="vim"
  local branch="main"

  prompt_default "Nombre para commits" "$name" name
  prompt_default "Email para commits" "$email" email

  while true; do
    prompt_default "Editor por defecto (vim, nano, code)" "$editor" editor
    case "$editor" in
      vim|nano|code) break ;;
      *) warn "Editor inválido. Usa: vim, nano o code." ;;
    esac
  done

  prompt_default "Branch por defecto" "$branch" branch

  local template="$DOTFILES_DIR/config/.gitconfig.template"
  local gitconfig="$HOME/.gitconfig"
  backup_file "$gitconfig"

  if [[ -f "$template" ]]; then
    step "Generar ~/.gitconfig desde template"
    sed \
      -e "s|{{NAME}}|$name|g" \
      -e "s|{{EMAIL}}|$email|g" \
      -e "s|{{EDITOR}}|$editor|g" \
      -e "s|{{DEFAULT_BRANCH}}|$branch|g" \
      "$template" >"$gitconfig"
    success "~/.gitconfig generado."
  else
    warn "No existe template $template. Generando gitconfig mínimo."
    cat >"$gitconfig" <<EOF
[user]
	name = $name
	email = $email
[core]
	editor = $editor
[init]
	defaultBranch = $branch
EOF
    success "~/.gitconfig generado (mínimo)."
  fi

  if confirm "¿Configurar SSH key para GitHub ahora?"; then
    local key="$HOME/.ssh/id_ed25519"
    mkdir -p "$HOME/.ssh"
    chmod 700 "$HOME/.ssh"

    if [[ -f "$key" ]]; then
      success "Ya existe una key: $key"
    else
      run_cmd "Generar SSH key (ed25519)" ssh-keygen -t ed25519 -C "$email" -f "$key"
    fi

    if [[ -f "$key.pub" ]]; then
      info "Copia esta clave pública en GitHub > SSH keys:"
      printf "\n%s\n\n" "$(cat "$key.pub")"
    fi
  fi
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  install_git
fi

