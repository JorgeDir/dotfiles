#!/usr/bin/env bash
set -euo pipefail

# This script is intended to be sourced from install.sh to reuse helpers.
# It can also be executed directly; in that case, it bootstraps minimal helpers.

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
fi

DOTFILES_DIR="${DOTFILES_DIR:-$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)}"

AWS_DIR="$HOME/.aws"
AWS_CONFIG="$AWS_DIR/config"
TEMPLATE="$DOTFILES_DIR/config/aws/config.template"

ensure_aws_dir() {
  mkdir -p "$AWS_DIR"
  [[ -f "$AWS_CONFIG" ]] || touch "$AWS_CONFIG"
}

print_header() {
  clear || true
  cat <<EOF
┌─────────────────────────────────────────────┐
│  CONFIGURADOR AWS SSO                        │
│  ~/.aws/config                               │
└─────────────────────────────────────────────┘
EOF
  printf "\n"
}

run_aws_cmd() {
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
}

list_profiles() {
  ensure_aws_dir
  # Profiles are [profile NAME]
  awk '
    /^\[profile[[:space:]]+/{
      gsub(/^\[profile[[:space:]]+/, "", $0);
      gsub(/\]$/, "", $0);
      print $0
    }' "$AWS_CONFIG" | sed '/^[[:space:]]*$/d'
}

list_sso_sessions() {
  ensure_aws_dir
  awk '
    /^\[sso-session[[:space:]]+/{
      gsub(/^\[sso-session[[:space:]]+/, "", $0);
      gsub(/\]$/, "", $0);
      print $0
    }' "$AWS_CONFIG" | sed '/^[[:space:]]*$/d'
}

show_current_config() {
  ensure_aws_dir
  info "Perfiles actuales en $AWS_CONFIG"
  if [[ ! -s "$AWS_CONFIG" ]]; then
    warn "El archivo está vacío."
    return 0
  fi
  printf "\n"
  sed -n '1,240p' "$AWS_CONFIG"
  if [[ $(wc -l <"$AWS_CONFIG") -gt 240 ]]; then
    printf "\n%s\n" "… (truncado; revisa el archivo completo en $AWS_CONFIG)"
  fi
  printf "\n"
}

backup_config() {
  ensure_aws_dir
  backup_file "$AWS_CONFIG"
}

escape_sed_repl() {
  # Escape replacement string for sed (/, &, \)
  printf '%s' "$1" | sed -e 's/[\/&\\]/\\&/g'
}

render_template_interactive() {
  local dev_profile="developer"
  local develops_profile="develops"
  local qa_profile="devops-qa"
  local uat_profile="devops-uat"
  local prod_profile="devops-prod"

  info "Vamos a parametrizar el template (solo nombres de perfiles)."

  printf "\n${CYAN}Perfil DEV${RESET}\n"
  prompt_default "Nombre del perfil" "$dev_profile" dev_profile
  local dev_aliases=""
  read -r -p "Aliases adicionales (coma-separados, opcional) [ej: jorge-dev]: " dev_aliases || true

  printf "\n${CYAN}Perfil DEVELOPS${RESET}\n"
  prompt_default "Nombre del perfil" "$develops_profile" develops_profile
  local develops_aliases=""
  read -r -p "Aliases adicionales (coma-separados, opcional): " develops_aliases || true

  printf "\n${CYAN}Perfil QA${RESET}\n"
  prompt_default "Nombre del perfil" "$qa_profile" qa_profile
  local qa_aliases=""
  read -r -p "Aliases adicionales (coma-separados, opcional): " qa_aliases || true

  printf "\n${CYAN}Perfil UAT${RESET}\n"
  prompt_default "Nombre del perfil" "$uat_profile" uat_profile
  local uat_aliases=""
  read -r -p "Aliases adicionales (coma-separados, opcional): " uat_aliases || true

  printf "\n${CYAN}Perfil PROD${RESET}\n"
  prompt_default "Nombre del perfil" "$prod_profile" prod_profile
  local prod_aliases=""
  read -r -p "Aliases adicionales (coma-separados, opcional): " prod_aliases || true

  local out
  out="$(sed \
    -e "s/{{DEV_PROFILE}}/$(escape_sed_repl "$dev_profile")/g" \
    -e "s/{{DEVELOPS_PROFILE}}/$(escape_sed_repl "$develops_profile")/g" \
    -e "s/{{QA_PROFILE}}/$(escape_sed_repl "$qa_profile")/g" \
    -e "s/{{UAT_PROFILE}}/$(escape_sed_repl "$uat_profile")/g" \
    -e "s/{{PROD_PROFILE}}/$(escape_sed_repl "$prod_profile")/g" \
    "$TEMPLATE")"

  # Si el usuario pidió aliases, duplicamos el bloque [profile ...] manteniendo el resto igual.
  # Esto permite: aws sso login --profile developer  y  aws sso login --profile jorge-dev
  add_profile_alias_blocks() {
    local base_name="$1"
    local aliases_csv="$2"
    local tmp_out="$3"

    local -a aliases=()
    local a
    IFS=',' read -r -a aliases <<<"$aliases_csv" || true
    for a in "${aliases[@]}"; do
      a="$(printf "%s" "$a" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
      [[ -z "$a" ]] && continue
      [[ "$a" == "$base_name" ]] && continue

      # Extract the base profile block and rewrite the header line.
      local block
      block="$(awk -v p="$base_name" '
        BEGIN{in=0}
        $0 ~ "^[[]profile[[:space:]]+" p "[]]$" {in=1; print; next}
        $0 ~ "^[[]" && in==1 {exit}
        in==1 {print}
      ' <<<"$tmp_out")"

      if [[ -z "$block" ]]; then
        warn "No se pudo encontrar el bloque del perfil base: $base_name (alias $a omitido)"
        continue
      fi

      block="$(printf "%s\n" "$block" | sed -e "1s/^[[]profile[[:space:]]\\+.*[]]$/[profile $a]/")"
      tmp_out="${tmp_out}"$'\n\n'"$block"
    done
    printf "%s" "$tmp_out"
  }

  out="$(add_profile_alias_blocks "$dev_profile" "$dev_aliases" "$out")"
  out="$(add_profile_alias_blocks "$develops_profile" "$develops_aliases" "$out")"
  out="$(add_profile_alias_blocks "$qa_profile" "$qa_aliases" "$out")"
  out="$(add_profile_alias_blocks "$uat_profile" "$uat_aliases" "$out")"
  out="$(add_profile_alias_blocks "$prod_profile" "$prod_aliases" "$out")"

  printf "\n${CYAN}Preview del config resultante:${RESET}\n\n"
  printf "%s\n" "$out" | sed -n '1,200p'
  if [[ $(printf "%s\n" "$out" | wc -l) -gt 200 ]]; then
    printf "\n… (truncado)\n"
  fi
  printf "\n"

  if ! confirm "¿Aplicar este config (reemplaza ~/.aws/config, con backup)?"; then
    warn "Importación parametrizada cancelada."
    return 0
  fi

  backup_config
  printf "%s\n" "$out" >"$AWS_CONFIG"
  success "Config generado desde template y aplicado en $AWS_CONFIG"
}

import_from_template() {
  ensure_aws_dir
  if [[ ! -f "$TEMPLATE" ]]; then
    error "No existe el template: $TEMPLATE"
    return 1
  fi
  info "Esto reemplazará COMPLETAMENTE tu $AWS_CONFIG por un template (con backup previo)."
  if ! confirm "¿Importar config completo desde template?"; then
    warn "Importación cancelada."
    return 0
  fi

  # Si el template contiene placeholders {{...}}, lo parametrizamos.
  if grep -q "{{DEV_PROFILE}}" "$TEMPLATE" 2>/dev/null; then
    render_template_interactive
    return 0
  fi

  backup_config
  cp -f "$TEMPLATE" "$AWS_CONFIG"
  success "Template importado a $AWS_CONFIG"
}

prompt_default() {
  local label="$1" default="$2" outvar="$3"
  local val=""
  read -r -p "$(printf "%s [%s]: " "$label" "$default")" val || true
  if [[ -z "${val}" ]]; then val="$default"; fi
  printf -v "$outvar" "%s" "$val"
}

select_from_list() {
  local title="$1"; shift
  local -a items=("$@")
  if [[ ${#items[@]} -eq 0 ]]; then
    return 1
  fi
  # IMPORTANT: This function is often used with command substitution:
  # selected="$(select_from_list ...)"
  # So we must print UI to stderr and ONLY print the selected value to stdout.
  printf "%s\n" "$title" >&2
  local i=1
  for it in "${items[@]}"; do
    printf "  %d. %s\n" "$i" "$it" >&2
    i=$((i+1))
  done
  local choice=""
  if [[ -t 0 ]]; then
    read -r -p "Elige número: " choice || true
  else
    # When stdin is captured (e.g., $(...)), read directly from the tty.
    read -r -p "Elige número: " choice </dev/tty || true
  fi
  if [[ ! "$choice" =~ ^[0-9]+$ ]] || (( choice < 1 || choice > ${#items[@]} )); then
    return 1
  fi
  printf "%s" "${items[$((choice-1))]}"
}

append_profile_block() {
  local block="$1"
  ensure_aws_dir
  printf "\n%s\n" "$block" >>"$AWS_CONFIG"
}

add_new_profile() {
  ensure_aws_dir
  info "Este wizard agregará un nuevo perfil SSO haciendo append (sin borrar lo existente)."
  if ! confirm "¿Agregar nuevo perfil SSO?"; then
    warn "Agregar perfil: cancelado."
    return 0
  fi

  local profile="developer"
  local account_id="606212394872"
  local role_name="Developer"
  local sso_start_url="https://d-90678f4040.awsapps.com/start"
  local sso_region="us-east-1"
  local profile_region="us-east-1"

  prompt_default "Nombre del perfil" "$profile" profile
  prompt_default "Account ID de AWS" "$account_id" account_id
  prompt_default "Nombre del rol IAM" "$role_name" role_name
  prompt_default "SSO Start URL" "$sso_start_url" sso_start_url
  prompt_default "SSO Region" "$sso_region" sso_region
  prompt_default "Region del perfil" "$profile_region" profile_region

  local create_session_ans=""
  read -r -p "¿Crear una sso-session separada para este perfil? [s/N]: " create_session_ans || true
  local create_session=false
  if [[ "${create_session_ans,,}" == "s" || "${create_session_ans,,}" == "si" || "${create_session_ans,,}" == "sí" ]]; then
    create_session=true
  fi

  local session_name=""
  if $create_session; then
    session_name="$profile"
  else
    mapfile -t sessions < <(list_sso_sessions || true)
    if [[ ${#sessions[@]} -gt 0 ]]; then
      local selected
      selected="$(select_from_list "Reutilizar sso-session existente:" "${sessions[@]}")" || true
      if [[ -n "${selected:-}" ]]; then
        session_name="$selected"
      else
        warn "Selección inválida. Se usará sso-session = $profile (puedes editar luego)."
        session_name="$profile"
        create_session=true
      fi
    else
      warn "No hay sso-sessions existentes. Se creará una nueva."
      session_name="$profile"
      create_session=true
    fi
  fi

  local profile_block
  profile_block="$(cat <<EOF
[profile ${profile}]
sso_session    = ${session_name}
sso_account_id = ${account_id}
sso_role_name  = ${role_name}
region         = ${profile_region}
EOF
)"

  local session_block=""
  if $create_session; then
    session_block="$(cat <<EOF

[sso-session ${session_name}]
sso_start_url = ${sso_start_url}
sso_region = ${sso_region}
sso_registration_scopes = sso:account:access
EOF
)"
  fi

  info "¿Agregar este perfil?"
  printf "\n%s\n" "$profile_block"
  if $create_session; then
    printf "%s\n" "$session_block"
  fi
  printf "\n"

  if ! confirm "¿Confirmas agregarlo?"; then
    warn "No se agregó el perfil."
    return 0
  fi

  backup_config

  append_profile_block "$profile_block"
  if $create_session; then
    append_profile_block "$session_block"
  fi
  success "Perfil agregado en $AWS_CONFIG"
}

delete_profile() {
  ensure_aws_dir
  mapfile -t profiles < <(list_profiles || true)
  if [[ ${#profiles[@]} -eq 0 ]]; then
    warn "No hay perfiles para eliminar."
    return 0
  fi
  local prof
  prof="$(select_from_list "Selecciona perfil a eliminar:" "${profiles[@]}")" || true
  if [[ -z "${prof:-}" ]]; then
    warn "Selección inválida."
    return 0
  fi
  info "Esto eliminará el bloque [profile $prof] del archivo (con backup)."
  if ! confirm "¿Eliminar perfil '$prof'?"; then
    warn "Eliminación cancelada."
    return 0
  fi
  backup_config

  local tmp; tmp="$(mktemp)"
  awk -v p="$prof" '
    BEGIN{skip=0}
    $0 ~ "^[[]profile[[:space:]]+" p "[]]$" {skip=1; next}
    $0 ~ "^[[]" && skip==1 {skip=0}
    skip==0 {print}
  ' "$AWS_CONFIG" >"$tmp"
  cp -f "$tmp" "$AWS_CONFIG"
  rm -f "$tmp"
  success "Perfil eliminado: $prof"
}

edit_profile() {
  ensure_aws_dir
  mapfile -t profiles < <(list_profiles || true)
  if [[ ${#profiles[@]} -eq 0 ]]; then
    warn "No hay perfiles para editar."
    return 0
  fi
  local prof
  prof="$(select_from_list "Selecciona perfil a editar:" "${profiles[@]}")" || true
  if [[ -z "${prof:-}" ]]; then
    warn "Selección inválida."
    return 0
  fi
  local editor="${EDITOR:-nano}"
  info "Se abrirá $AWS_CONFIG en el editor: $editor"
  warn "Busca el bloque [profile $prof] y edítalo manualmente."
  if ! confirm "¿Abrir editor ahora?"; then
    warn "Edición cancelada."
    return 0
  fi
  backup_config
  "$editor" "$AWS_CONFIG"
  success "Edición finalizada (si guardaste cambios)."
}

test_login() {
  ensure_aws_dir
  if ! command -v aws >/dev/null 2>&1; then
    error "No se encontró 'aws' en PATH. Instala AWS CLI primero."
    return 1
  fi
  mapfile -t profiles < <(list_profiles || true)
  if [[ ${#profiles[@]} -eq 0 ]]; then
    warn "No hay perfiles SSO en $AWS_CONFIG."
    return 0
  fi
  local prof
  prof="$(select_from_list "Selecciona perfil para probar login:" "${profiles[@]}")" || true
  if [[ -z "${prof:-}" ]]; then
    warn "Selección inválida."
    return 0
  fi
  info "Probando login con perfil: $prof"
  run_aws_cmd "aws sso login --profile $prof" aws sso login --profile "$prof"
  run_aws_cmd "Validar identidad (sts get-caller-identity)" aws sts get-caller-identity --profile "$prof"
  success "Login OK para perfil: $prof"
}

configure_aws_sso() {
  info "Este módulo gestiona perfiles AWS SSO en $AWS_CONFIG."
  info "Log: $DOTFILES_LOG_FILE"
  if ! confirm "¿Abrir configurador AWS SSO?"; then
    warn "AWS SSO: cancelado."
    return 0
  fi

  ensure_aws_dir
  if [[ -s "$AWS_CONFIG" ]]; then
    warn "Se detectó un $AWS_CONFIG existente."
    info "Nada se sobrescribe automáticamente: 'Agregar' hace append; 'Importar template' reemplaza (con backup)."
    if confirm "¿Hacer un backup ahora antes de continuar?"; then
      backup_config
    fi
  fi
  while true; do
    print_header
    cat <<'EOF'
¿Qué deseas hacer?
  1. Ver perfiles actuales
  2. Agregar nuevo perfil SSO
  3. Eliminar perfil
  4. Editar perfil existente
  5. Importar config completo desde template
  6. Hacer backup del config actual
  7. Probar login de un perfil
  q. Volver al menú principal
EOF
    printf "\n"
    local choice=""
    read -r -p "Opción: " choice || true
    case "${choice,,}" in
      1) show_current_config; read -r -p "Enter para continuar..." _ || true ;;
      2) add_new_profile; read -r -p "Enter para continuar..." _ || true ;;
      3) delete_profile; read -r -p "Enter para continuar..." _ || true ;;
      4) edit_profile; read -r -p "Enter para continuar..." _ || true ;;
      5) import_from_template; read -r -p "Enter para continuar..." _ || true ;;
      6) backup_config; read -r -p "Enter para continuar..." _ || true ;;
      7) test_login; read -r -p "Enter para continuar..." _ || true ;;
      q) return 0 ;;
      *) warn "Opción inválida: $choice"; sleep 1 ;;
    esac
  done
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  configure_aws_sso
fi

