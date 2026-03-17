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

# NoSQLBooster: Linux se distribuye como AppImage (requiere FUSE v2)
NOSQLBOOSTER_APPIMAGE_URL="${NOSQLBOOSTER_APPIMAGE_URL:-https://s3.nosqlbooster.com/download/releasesv10/nosqlbooster4mongo-10.1.4.AppImage}"
NOSQLBOOSTER_DIR="${HOME}/.local/share/nosqlbooster"

install_gui_tools() {
  info "Este módulo instalará DBeaver CE (snap o apt) y NoSQLBooster (AppImage)."
  info "Log: $DOTFILES_LOG_FILE"
  if ! confirm "¿Instalar GUI Tools?"; then
    warn "GUI Tools: cancelado."
    return 0
  fi

  # DBeaver CE: intentar snap, luego APT (PPA)
  if command -v dbeaver >/dev/null 2>&1 || (command -v snap >/dev/null 2>&1 && snap list 2>/dev/null | awk '{print $1}' | grep -qx "dbeaver-ce"); then
    success "DBeaver CE ya está instalado."
  elif command -v snap >/dev/null 2>&1; then
    step "Instalar DBeaver CE (snap)"
    _log "[CMD] sudo snap install dbeaver-ce"
    if sudo snap install dbeaver-ce >>"$DOTFILES_LOG_FILE" 2>&1; then
      success "Instalar DBeaver CE (snap)"
    else
      warn "Snap falló. Intentando DBeaver CE por APT (PPA)..."
      step "Añadir PPA e instalar DBeaver CE (apt)"
      _log "[CMD] add-apt-repository + apt install dbeaver-ce"
      if (sudo add-apt-repository -y ppa:serge-rider/dbeaver-ce >>"$DOTFILES_LOG_FILE" 2>&1 && sudo apt-get update -y >>"$DOTFILES_LOG_FILE" 2>&1 && sudo apt-get install -y dbeaver-ce >>"$DOTFILES_LOG_FILE" 2>&1); then
        success "DBeaver CE instalado (apt)."
      else
        warn "Instala DBeaver manualmente: https://dbeaver.io o sudo apt install dbeaver-ce (tras PPA serge-rider/dbeaver-ce)"
      fi
    fi
  else
    step "Instalar DBeaver CE (APT PPA)"
    _log "[CMD] add-apt-repository + apt install dbeaver-ce"
    if (sudo add-apt-repository -y ppa:serge-rider/dbeaver-ce >>"$DOTFILES_LOG_FILE" 2>&1 && sudo apt-get update -y >>"$DOTFILES_LOG_FILE" 2>&1 && sudo apt-get install -y dbeaver-ce >>"$DOTFILES_LOG_FILE" 2>&1); then
      success "DBeaver CE instalado (apt)."
    else
      warn "DBeaver CE no instalado. Prueba: sudo snap install dbeaver-ce o https://dbeaver.io"
    fi
  fi

  # NoSQLBooster: AppImage (Linux). Requiere libfuse2 en Ubuntu 22.04+
  local appimage="$NOSQLBOOSTER_DIR/nosqlbooster4mongo.AppImage"
  if command -v nosqlbooster4mongo >/dev/null 2>&1 || [[ -x "$appimage" ]]; then
    success "NoSQLBooster ya está instalado."
    # Asegurar entrada en el menú si falta
    if [[ -x "$appimage" ]] && [[ ! -f "$HOME/.local/share/applications/nosqlbooster4mongo.desktop" ]]; then
      mkdir -p "$HOME/.local/share/applications"
      cat > "$HOME/.local/share/applications/nosqlbooster4mongo.desktop" << DESKTOP
[Desktop Entry]
Name=NoSQLBooster for MongoDB
Comment=GUI client for MongoDB
Exec=$appimage
Icon=database
Type=Application
Categories=Development;Database;
StartupNotify=true
DESKTOP
      success "Entrada de menú creada para NoSQLBooster."
    fi
  else
    step "Instalar dependencia FUSE (libfuse2)"
    _log "[CMD] sudo apt-get install -y libfuse2"
    sudo apt-get install -y libfuse2 >>"$DOTFILES_LOG_FILE" 2>&1 || true
    mkdir -p "$NOSQLBOOSTER_DIR"
    step "Descargar NoSQLBooster (AppImage)"
    _log "[CMD] curl -fsSL $NOSQLBOOSTER_APPIMAGE_URL -o $appimage"
    if curl -fsSL "$NOSQLBOOSTER_APPIMAGE_URL" -o "$appimage" >>"$DOTFILES_LOG_FILE" 2>&1; then
      chmod +x "$appimage"
      success "NoSQLBooster descargado en $appimage"
      if [[ -d "$HOME/.local/bin" ]] && [[ ! -e "$HOME/.local/bin/nosqlbooster4mongo" ]]; then
        ln -sf "$appimage" "$HOME/.local/bin/nosqlbooster4mongo"
        success "Ejecutable: nosqlbooster4mongo (en PATH si ~/.local/bin está)"
      fi
      # Entrada en el menú de aplicaciones
      mkdir -p "$HOME/.local/share/applications"
      cat > "$HOME/.local/share/applications/nosqlbooster4mongo.desktop" << DESKTOP
[Desktop Entry]
Name=NoSQLBooster for MongoDB
Comment=GUI client for MongoDB
Exec=$appimage
Icon=database
Type=Application
Categories=Development;Database;
StartupNotify=true
DESKTOP
      success "NoSQLBooster añadido al menú de aplicaciones."
      info "Ejecuta: $appimage  o  nosqlbooster4mongo  o búscalo en el menú"
    else
      warn "Descarga falló. Instala manualmente: https://nosqlbooster.com/downloads (AppImage, requiere libfuse2)"
    fi
  fi
  success "GUI Tools listos."
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  install_gui_tools
fi

