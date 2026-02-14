#!/usr/bin/env bash
# ──────────────────────────────────────────────────────────────────────────────
# XRAY TUNNEL MANAGER PRO (VMess+WS + Reverse Portal)
# - Topo “orquestrado” e bem separado
# - Vistoria automática (testa todos os sites ao entrar no menu + intervalo)
# - Teste em TODOS os sites (lista nome|url), com HTTP code + tempo
# - Portas dinâmicas (túnel/socks), WS path dinâmico
# - Port Doctor (porta presa / processo ouvindo)
# - Mantém UUID fixo
# ──────────────────────────────────────────────────────────────────────────────

set -Eeuo pipefail

# =========================
# CORES / UI
# =========================
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
DIM='\033[2m'
NC='\033[0m'

hr() {
  local w="${COLUMNS:-100}"
  printf "${DIM}%*s${NC}\n" "$w" "" | tr ' ' '─'
}
pause() { read -r -p "Enter para continuar..." _; }
icon_ok() { echo -e "${GREEN}●${NC}"; }
icon_bad(){ echo -e "${RED}●${NC}"; }
icon_warn(){ echo -e "${YELLOW}●${NC}"; }

# =========================
# ARQUIVOS / PATHS
# =========================
UUID_FILE="/root/.xray_uuid_fixed"
CONFIG_FILE="/usr/local/etc/xray/config.json"
SETTINGS_FILE="/root/.xray_tunnel_manager.env"
STATE_FILE="/root/.xray_tunnel_manager.state"

# Lista externa opcional (mais “profissional”):
# cada linha: NOME|URL
SITES_FILE="/root/.xray_sites.list"

XRAY_BIN="/usr/local/bin/xray"
SERVICE="xray"

# =========================
# PADRÕES
# =========================
PORT_TUNNEL_DEFAULT=80
PORT_SOCKS_DEFAULT=10800
WS_PATH_DEFAULT="/tunnel"
REVERSE_DOMAIN_DEFAULT="reverse.intranet"

# Auditoria
AUTO_AUDIT_ON_START_DEFAULT=1
AUTO_AUDIT_INTERVAL_DEFAULT=300   # segundos (5 min)
CONNECT_TIMEOUT_DEFAULT=3
MAX_TIME_DEFAULT=8
MAX_REDIRS_DEFAULT=4

# =========================
# SETTINGS (persistentes)
# =========================
PORT_TUNNEL="$PORT_TUNNEL_DEFAULT"
PORT_SOCKS="$PORT_SOCKS_DEFAULT"
WS_PATH="$WS_PATH_DEFAULT"
REVERSE_DOMAIN="$REVERSE_DOMAIN_DEFAULT"

AUTO_AUDIT_ON_START="$AUTO_AUDIT_ON_START_DEFAULT"
AUTO_AUDIT_INTERVAL="$AUTO_AUDIT_INTERVAL_DEFAULT"
CONNECT_TIMEOUT="$CONNECT_TIMEOUT_DEFAULT"
MAX_TIME="$MAX_TIME_DEFAULT"
MAX_REDIRS="$MAX_REDIRS_DEFAULT"

# STATE (persistente)
LAST_AUDIT_EPOCH=""
LAST_AUDIT_AT=""
AUDIT_SUMMARY=""

# RESULTADOS (memória)
declare -a SITE_NAME SITE_URL SITE_CODE SITE_TIME SITE_STATUS SITE_NOTE

# =========================
# HELPERS
# =========================
require_root() {
  if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
    echo -e "${RED}[ERRO] Rode como root.${NC} Ex: sudo bash $0"
    exit 1
  fi
}

have_cmd() { command -v "$1" >/dev/null 2>&1; }

get_ip() {
  local ip=""
  ip="$(curl -4s --max-time 3 ifconfig.me 2>/dev/null || true)"
  [[ -z "$ip" ]] && ip="$(curl -4s --max-time 3 icanhazip.com 2>/dev/null || true)"
  echo "$ip"
}

fmt_dt() { date '+%d/%m/%Y %H:%M:%S'; }

age_human() {
  local now epoch diff
  now="$(date +%s)"
  epoch="${1:-0}"
  (( epoch <= 0 )) && { echo "nunca"; return; }
  diff=$(( now - epoch ))
  if (( diff < 60 )); then echo "há ${diff}s"
  elif (( diff < 3600 )); then echo "há $((diff/60)) min"
  elif (( diff < 86400 )); then echo "há $((diff/3600)) h"
  else echo "há $((diff/86400)) d"
  fi
}

ensure_uuid() {
  if [[ -f "$UUID_FILE" ]]; then
    UUID="$(cat "$UUID_FILE")"
  else
    UUID="$(cat /proc/sys/kernel/random/uuid)"
    echo "$UUID" > "$UUID_FILE"
  fi
}

load_settings() {
  if [[ -f "$SETTINGS_FILE" ]]; then
    # shellcheck disable=SC1090
    source "$SETTINGS_FILE"
  fi
  if [[ -f "$STATE_FILE" ]]; then
    # shellcheck disable=SC1090
    source "$STATE_FILE"
  fi

  PORT_TUNNEL="${PORT_TUNNEL:-$PORT_TUNNEL_DEFAULT}"
  PORT_SOCKS="${PORT_SOCKS:-$PORT_SOCKS_DEFAULT}"
  WS_PATH="${WS_PATH:-$WS_PATH_DEFAULT}"
  REVERSE_DOMAIN="${REVERSE_DOMAIN:-$REVERSE_DOMAIN_DEFAULT}"

  AUTO_AUDIT_ON_START="${AUTO_AUDIT_ON_START:-$AUTO_AUDIT_ON_START_DEFAULT}"
  AUTO_AUDIT_INTERVAL="${AUTO_AUDIT_INTERVAL:-$AUTO_AUDIT_INTERVAL_DEFAULT}"
  CONNECT_TIMEOUT="${CONNECT_TIMEOUT:-$CONNECT_TIMEOUT_DEFAULT}"
  MAX_TIME="${MAX_TIME:-$MAX_TIME_DEFAULT}"
  MAX_REDIRS="${MAX_REDIRS:-$MAX_REDIRS_DEFAULT}"

  LAST_AUDIT_EPOCH="${LAST_AUDIT_EPOCH:-}"
  LAST_AUDIT_AT="${LAST_AUDIT_AT:-}"
  AUDIT_SUMMARY="${AUDIT_SUMMARY:-}"
}

save_settings() {
  cat > "$SETTINGS_FILE" <<EOF
# XRAY TUNNEL MANAGER - SETTINGS
PORT_TUNNEL=${PORT_TUNNEL}
PORT_SOCKS=${PORT_SOCKS}
WS_PATH=$(printf "%q" "$WS_PATH")
REVERSE_DOMAIN=$(printf "%q" "$REVERSE_DOMAIN")

AUTO_AUDIT_ON_START=${AUTO_AUDIT_ON_START}
AUTO_AUDIT_INTERVAL=${AUTO_AUDIT_INTERVAL}
CONNECT_TIMEOUT=${CONNECT_TIMEOUT}
MAX_TIME=${MAX_TIME}
MAX_REDIRS=${MAX_REDIRS}
EOF
}

save_state() {
  cat > "$STATE_FILE" <<EOF
# XRAY TUNNEL MANAGER - STATE
LAST_AUDIT_EPOCH=$(printf "%q" "$LAST_AUDIT_EPOCH")
LAST_AUDIT_AT=$(printf "%q" "$LAST_AUDIT_AT")
AUDIT_SUMMARY=$(printf "%q" "$AUDIT_SUMMARY")
EOF
}

ensure_deps() {
  apt-get update -y >/dev/null 2>&1 || true
  apt-get install -y curl jq net-tools psmisc lsof >/dev/null 2>&1 || true
}

service_active() { systemctl is-active --quiet "$SERVICE"; }

port_listen_info() {
  local port="$1"
  local out=""
  if have_cmd ss; then
    out="$(ss -Hltnp "sport = :$port" 2>/dev/null | awk '{print $NF}' | head -n1 || true)"
  fi
  if [[ -z "$out" ]]; then
    out="$(lsof -nP -iTCP:"$port" -sTCP:LISTEN 2>/dev/null | awk 'NR==2{print $2"/"$1}' || true)"
  fi
  echo "$out"
}
port_is_listening() { [[ -n "$(port_listen_info "$1")" ]]; }

bridge_is_online() {
  local port="$1"
  local n=0
  if have_cmd ss; then
    n="$(ss -Htn state established "( sport = :$port )" 2>/dev/null | wc -l | tr -d ' ' || true)"
  else
    n="$(netstat -tn 2>/dev/null | awk '{print $6,$4}' | grep -E "ESTABLISHED .*:${port}$" -c || true)"
  fi
  [[ "${n:-0}" -gt 0 ]]
}

kill_port() {
  local port="$1"
  if have_cmd fuser; then
    fuser -k "${port}/tcp" >/dev/null 2>&1 || true
  else
    lsof -t -iTCP:"$port" -sTCP:LISTEN 2>/dev/null | xargs -r kill -9 >/dev/null 2>&1 || true
  fi
}

force_cleanup_ports() {
  echo -e "${YELLOW}[*] Parando serviço e limpando portas ${PORT_TUNNEL}/${PORT_SOCKS}...${NC}"
  systemctl stop "$SERVICE" >/dev/null 2>&1 || true
  kill_port "$PORT_TUNNEL"
  kill_port "$PORT_SOCKS"
  echo -e "${GREEN}[OK] Portas liberadas.${NC}"
}

apply_setcap_if_needed() {
  if [[ -x "$XRAY_BIN" ]]; then
    setcap CAP_NET_BIND_SERVICE=+eip "$XRAY_BIN" >/dev/null 2>&1 || true
  fi
}

# =========================
# SITES (DEFAULT + EXTERNO)
# =========================
load_sites() {
  SITE_NAME=()
  SITE_URL=()

  if [[ -f "$SITES_FILE" ]]; then
    while IFS= read -r line; do
      [[ -z "$line" ]] && continue
      [[ "$line" =~ ^[[:space:]]*# ]] && continue
      IFS='|' read -r n u <<<"$line"
      n="${n:-}"; u="${u:-}"
      [[ -z "$n" || -z "$u" ]] && continue
      SITE_NAME+=("$n")
      SITE_URL+=("$u")
    done < "$SITES_FILE"
  fi

  # se não tiver arquivo externo ou veio vazio, usa defaults:
  if (( ${#SITE_NAME[@]} == 0 )); then
    SITE_NAME+=("INTRANET (HOME)")
    SITE_URL+=("http://intranet.policiamilitar.sp.gov.br/")

    SITE_NAME+=("COPOM ONLINE")
    SITE_URL+=("https://copomonline.policiamilitar.sp.gov.br/Login/Login")

    SITE_NAME+=("MURALHA PAULISTA")
    SITE_URL+=("https://operacional.muralhapaulista.sp.gov.br/Home/Login")

    SITE_NAME+=("SIOPM-WEB")
    SITE_URL+=("http://sistemasopr.intranet.policiamilitar.sp.gov.br/siopmweb/HSiopm.aspx")

    SITE_NAME+=("INFOCRIM")
    SITE_URL+=("https://www.infocrim.ssp.sp.gov.br/login")
  fi
}

# =========================
# XRAY CONFIG (SERVER)
# =========================
write_server_config() {
  mkdir -p "$(dirname "$CONFIG_FILE")"
  cat > "$CONFIG_FILE" <<EOF
{
  "log": {
    "loglevel": "warning",
    "access": "/var/log/xray/access.log",
    "error": "/var/log/xray/error.log"
  },
  "reverse": {
    "portals": [
      { "tag": "portal", "domain": "$REVERSE_DOMAIN" }
    ]
  },
  "inbounds": [
    {
      "tag": "interceptor",
      "port": $PORT_SOCKS,
      "protocol": "socks",
      "settings": { "auth": "noauth", "udp": true },
      "sniffing": { "enabled": true, "destOverride": ["http","tls"] }
    },
    {
      "tag": "tunnel-in",
      "port": $PORT_TUNNEL,
      "protocol": "vmess",
      "settings": { "clients": [ { "id": "$UUID", "alterId": 0 } ] },
      "streamSettings": {
        "network": "ws",
        "wsSettings": { "path": "$WS_PATH" }
      }
    }
  ],
  "routing": {
    "rules": [
      { "type": "field", "inboundTag": ["interceptor"], "outboundTag": "portal" },
      { "type": "field", "inboundTag": ["tunnel-in"], "outboundTag": "portal" }
    ]
  }
}
EOF
}

restart_xray() {
  systemctl restart "$SERVICE" >/dev/null 2>&1 || true
  sleep 1
}

install_or_repair() {
  clear
  echo -e "${BLUE}${WHITE}INSTALAR / REPARAR XRAY (PORTAL)${NC}"
  hr
  ensure_deps

  echo -e "${YELLOW}[*] Instalando/atualizando Xray oficial...${NC}"
  bash -c "$(curl -fsSL https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install >/dev/null 2>&1 || true

  force_cleanup_ports
  echo -e "${YELLOW}[*] Gerando config e reiniciando...${NC}"
  write_server_config
  apply_setcap_if_needed
  systemctl enable "$SERVICE" >/dev/null 2>&1 || true
  restart_xray

  if service_active; then
    echo -e "${GREEN}[OK] Xray ONLINE.${NC}"
  else
    echo -e "${RED}[ERRO] Xray OFFLINE.${NC} Veja: journalctl -u $SERVICE -n 120 --no-pager"
  fi
  pause
}

# =========================
# CLIENT JSON (WINDOWS)
# =========================
show_client_json() {
  local vps_ip="$1"
  clear
  echo -e "${CYAN}${WHITE}CONFIG DO WINDOWS (BRIDGE)${NC}"
  hr
  echo -e "${DIM}Copie e salve como config.json:${NC}\n"

  cat <<EOF
{
  "log": { "loglevel": "warning" },
  "reverse": {
    "bridges": [ { "tag": "bridge", "domain": "$REVERSE_DOMAIN" } ]
  },
  "outbounds": [
    {
      "tag": "tunnel-out",
      "protocol": "vmess",
      "settings": {
        "vnext": [
          {
            "address": "$vps_ip",
            "port": $PORT_TUNNEL,
            "users": [ { "id": "$UUID", "alterId": 0, "security": "auto" } ]
          }
        ]
      },
      "streamSettings": { "network": "ws", "wsSettings": { "path": "$WS_PATH" } }
    },
    { "tag": "out", "protocol": "freedom" }
  ],
  "routing": {
    "rules": [
      { "type": "field", "domain": ["full:$REVERSE_DOMAIN"], "outboundTag": "tunnel-out" },
      { "type": "field", "inboundTag": ["bridge"], "outboundTag": "out" }
    ]
  }
}
EOF

  echo
  hr
  echo -e "${DIM}Se mudar portas/path no menu da VPS, gere este JSON novamente.${NC}"
  pause
}

# =========================
# TESTES (TODOS OS SITES) via SOCKS local
# =========================
is_ok_code() {
  local c="$1"
  [[ "$c" == "200" || "$c" == "301" || "$c" == "302" || "$c" == "401" || "$c" == "403" ]]
}

run_one_test_to_file() {
  # roda em subshell (não pode derrubar o script)
  local name="$1" url="$2" out="$3"
  (
    set +e
    local res code t err
    res="$(curl -k -sS -L --max-redirs "$MAX_REDIRS" \
      --connect-timeout "$CONNECT_TIMEOUT" --max-time "$MAX_TIME" \
      --proxy "socks5h://127.0.0.1:${PORT_SOCKS}" \
      -o /dev/null -w "%{http_code}|%{time_total}" \
      "$url" 2>/tmp/.xray_tm_err.$$ )"
    local rc=$?
    if [[ $rc -ne 0 ]]; then
      err="$(tr '\n' ' ' </tmp/.xray_tm_err.$$ | sed 's/[[:space:]]\+/ /g' | cut -c1-140)"
      echo "ERR|0|$err" > "$out"
      rm -f /tmp/.xray_tm_err.$$ >/dev/null 2>&1 || true
      exit 0
    fi
    rm -f /tmp/.xray_tm_err.$$ >/dev/null 2>&1 || true
    code="${res%%|*}"
    t="${res##*|}"
    echo "${code}|${t}|OK" > "$out"
    exit 0
  ) &
}

audit_all_sites() {
  load_sites

  SITE_CODE=(); SITE_TIME=(); SITE_STATUS=(); SITE_NOTE=()

  local n="${#SITE_NAME[@]}"
  (( n == 0 )) && return 0

  local tmpdir="/tmp/xray_tm_audit.$$"
  mkdir -p "$tmpdir"

  # dispara tudo em paralelo
  for i in "${!SITE_NAME[@]}"; do
    run_one_test_to_file "${SITE_NAME[$i]}" "${SITE_URL[$i]}" "$tmpdir/$i"
  done

  # aguarda
  wait || true

  local ok=0 fail=0
  for i in "${!SITE_NAME[@]}"; do
    local line code t note
    line="$(cat "$tmpdir/$i" 2>/dev/null || echo 'ERR|0|no output')"
    IFS='|' read -r code t note <<<"$line"

    SITE_CODE[$i]="$code"
    SITE_TIME[$i]="$t"
    SITE_NOTE[$i]="$note"

    if [[ "$code" == "ERR" || "$code" == "000" ]]; then
      SITE_STATUS[$i]="FAIL"
      ((fail++))
    else
      if is_ok_code "$code"; then
        SITE_STATUS[$i]="OK"
        ((ok++))
      else
        SITE_STATUS[$i]="WARN"
        ((fail++))
      fi
    fi
  done

  rm -rf "$tmpdir" >/dev/null 2>&1 || true

  LAST_AUDIT_EPOCH="$(date +%s)"
  LAST_AUDIT_AT="$(fmt_dt)"
  AUDIT_SUMMARY="${ok}/${n} OK"

  save_state
}

audit_if_needed() {
  local force="${1:-0}"
  local now epoch interval
  now="$(date +%s)"
  epoch="${LAST_AUDIT_EPOCH:-0}"
  interval="${AUTO_AUDIT_INTERVAL:-300}"

  if (( force == 1 )); then
    audit_all_sites
    return
  fi

  # se nunca auditou → audita
  if [[ -z "${LAST_AUDIT_EPOCH:-}" ]]; then
    audit_all_sites
    return
  fi

  # se passou do intervalo → audita
  if (( now - epoch >= interval )); then
    audit_all_sites
  fi
}

# =========================
# HEADER (TOPO ORQUESTRADO)
# =========================
badge_line() {
  local label="$1" ok="$2" extra="${3:-}"
  if [[ "$ok" == "1" ]]; then
    printf "%b %-16s %b %-30s\n" "$(icon_ok)" "${label}:" "${GREEN}OK${NC}" "${extra}"
  else
    printf "%b %-16s %b %-30s\n" "$(icon_bad)" "${label}:" "${RED}OFF${NC}" "${extra}"
  fi
}

render_header() {
  local vps_ip="$1"

  local srv="0" tnl="0" sks="0" br="0"
  service_active && srv="1"
  port_is_listening "$PORT_TUNNEL" && tnl="1"
  port_is_listening "$PORT_SOCKS" && sks="1"
  bridge_is_online "$PORT_TUNNEL" && br="1"

  clear
  echo -e "${BLUE}${WHITE}XRAY TUNNEL MANAGER PRO${NC}  ${DIM}(VMess+WS + Reverse Portal)${NC}"
  hr

  echo -e "${WHITE}Identificação${NC}"
  printf "  %-14s %b\n" "VPS IP:" "${CYAN}${vps_ip:-N/A}${NC}"
  printf "  %-14s %b\n" "UUID:"   "${CYAN}${UUID}${NC}"
  echo

  echo -e "${WHITE}Configuração${NC}"
  printf "  %-14s %b\n" "Túnel:"   "${CYAN}${PORT_TUNNEL}${NC}  ${DIM}(VMess+WS)${NC}"
  printf "  %-14s %b\n" "SOCKS:"   "${CYAN}${PORT_SOCKS}${NC}  ${DIM}(curl interno)${NC}"
  printf "  %-14s %b\n" "WS Path:" "${CYAN}${WS_PATH}${NC}"
  printf "  %-14s %b\n" "Domain:"  "${CYAN}${REVERSE_DOMAIN}${NC}"
  echo

  echo -e "${WHITE}Status operacional${NC}"
  badge_line "Serviço Xray" "$srv" "systemd: ${SERVICE}"
  badge_line "Porta Túnel"  "$tnl" "$(port_listen_info "$PORT_TUNNEL" || true)"
  badge_line "Porta SOCKS"  "$sks" "$(port_listen_info "$PORT_SOCKS" || true)"
  badge_line "Bridge"       "$br"  "Windows conectado ao túnel"

  echo
  echo -e "${WHITE}Vistoria (curl via SOCKS)${NC}"
  if [[ -n "${LAST_AUDIT_AT:-}" ]]; then
    printf "  %-14s %b\n" "Última:" "${CYAN}${LAST_AUDIT_AT}${NC}  ${DIM}(${age_human "$LAST_AUDIT_EPOCH"})${NC}"
    printf "  %-14s %b\n" "Resumo:" "${CYAN}${AUDIT_SUMMARY}${NC}"
  else
    printf "  %-14s %b\n" "Última:" "${DIM}nenhuma (ainda)${NC}"
  fi
  echo

  # Lista resultados (linha a linha)
  local n="${#SITE_NAME[@]}"
  if (( n > 0 )) && (( ${#SITE_CODE[@]} == n )); then
    for i in "${!SITE_NAME[@]}"; do
      local st="${SITE_STATUS[$i]:-}"
      local code="${SITE_CODE[$i]:-}"
      local t="${SITE_TIME[$i]:-}"
      local name="${SITE_NAME[$i]}"
      local url="${SITE_URL[$i]}"

      if [[ "$st" == "OK" ]]; then
        printf "  %b %b %-18s %b HTTP:%b %-3s %b %ss\n" \
          "$(icon_ok)" "${WHITE}" "${name}" "${DIM}" "${GREEN}" "${code}" "${DIM}" "${t}"
      elif [[ "$st" == "WARN" ]]; then
        printf "  %b %b %-18s %b HTTP:%b %-3s %b %ss\n" \
          "$(icon_warn)" "${WHITE}" "${name}" "${DIM}" "${YELLOW}" "${code}" "${DIM}" "${t}"
      else
        printf "  %b %b %-18s %b HTTP:%b %-3s %b %ss  %b\n" \
          "$(icon_bad)" "${WHITE}" "${name}" "${DIM}" "${RED}" "${code}" "${DIM}" "${t}" "${DIM}${SITE_NOTE[$i]:-}${NC}"
      fi
      printf "     %b\n" "${DIM}${url}${NC}"
    done
  else
    echo -e "  ${DIM}(resultados ainda não carregados)${NC}"
  fi

  hr
}

# =========================
# MENUS (mais “premium”)
# =========================
is_valid_port() {
  local p="$1"
  [[ "$p" =~ ^[0-9]+$ ]] && (( p >= 1 && p <= 65535 ))
}

change_ports() {
  clear
  echo -e "${YELLOW}${WHITE}ALTERAR PORTAS${NC}"
  hr
  echo -e "Atual:\n  - Túnel: ${CYAN}${PORT_TUNNEL}${NC}\n  - SOCKS: ${CYAN}${PORT_SOCKS}${NC}\n"
  local new_t new_s
  read -r -p "Nova porta do Túnel [${PORT_TUNNEL}]: " new_t
  read -r -p "Nova porta do SOCKS [${PORT_SOCKS}]: " new_s
  new_t="${new_t:-$PORT_TUNNEL}"
  new_s="${new_s:-$PORT_SOCKS}"

  if ! is_valid_port "$new_t" || ! is_valid_port "$new_s"; then
    echo -e "${RED}[ERRO] Portas inválidas. Use 1-65535.${NC}"
    pause
    return
  fi

  PORT_TUNNEL="$new_t"
  PORT_SOCKS="$new_s"
  save_settings

  echo
  echo -e "${YELLOW}[*] Aplicando e reiniciando...${NC}"
  force_cleanup_ports
  write_server_config
  apply_setcap_if_needed
  restart_xray
  pause
}

change_ws_path() {
  clear
  echo -e "${YELLOW}${WHITE}ALTERAR WS PATH${NC}"
  hr
  echo -e "Atual: ${CYAN}${WS_PATH}${NC}\n"
  local p
  read -r -p "Novo WS path (ex: /tunnel) [${WS_PATH}]: " p
  p="${p:-$WS_PATH}"
  [[ "$p" != /* ]] && p="/$p"

  WS_PATH="$p"
  save_settings

  echo
  echo -e "${YELLOW}[*] Aplicando e reiniciando...${NC}"
  force_cleanup_ports
  write_server_config
  apply_setcap_if_needed
  restart_xray
  pause
}

diagnostico() {
  local vps_ip="$1"
  clear
  echo -e "${CYAN}${WHITE}DIAGNÓSTICO COMPLETO${NC}"
  hr
  echo -e "${WHITE}VPS:${NC}  $vps_ip"
  echo -e "${WHITE}UUID:${NC} $UUID"
  echo

  echo -e "${WHITE}Serviço:${NC}"
  if service_active; then
    echo -e "  $(icon_ok) ${GREEN}Xray ONLINE${NC}"
  else
    echo -e "  $(icon_bad) ${RED}Xray OFFLINE${NC}"
  fi
  echo

  echo -e "${WHITE}Portas:${NC}"
  local li_t li_s
  li_t="$(port_listen_info "$PORT_TUNNEL")"
  li_s="$(port_listen_info "$PORT_SOCKS")"
  echo -e "  - Túnel ${PORT_TUNNEL}: ${li_t:+${GREEN}ABERTA${NC} (${DIM}${li_t}${NC})}${li_t:+' '}${li_t:-${RED}FECHADA${NC}}"
  echo -e "  - SOCKS ${PORT_SOCKS}: ${li_s:+${GREEN}ABERTA${NC} (${DIM}${li_s}${NC})}${li_s:+' '}${li_s:-${RED}FECHADA${NC}}"
  echo

  echo -e "${WHITE}Bridge:${NC}"
  if bridge_is_online "$PORT_TUNNEL"; then
    echo -e "  $(icon_ok) ${GREEN}CONECTADO${NC}"
  else
    echo -e "  $(icon_bad) ${RED}DESCONECTADO${NC}"
  fi
  echo
  echo -e "${DIM}Logs:${NC} journalctl -u $SERVICE -n 120 --no-pager"
  pause
}

port_doctor() {
  clear
  echo -e "${YELLOW}${WHITE}PORT DOCTOR${NC}"
  hr
  local a b
  a="$(port_listen_info "$PORT_TUNNEL")"
  b="$(port_listen_info "$PORT_SOCKS")"

  echo -e "${WHITE}Diagnóstico:${NC}"
  echo -e "  - Túnel ${PORT_TUNNEL}: ${a:-${DIM}(não está em LISTEN)${NC}}"
  echo -e "  - SOCKS ${PORT_SOCKS}: ${b:-${DIM}(não está em LISTEN)${NC}}"
  echo
  echo -e "${WHITE}Ações:${NC}"
  echo -e "  1) Kill na porta do Túnel"
  echo -e "  2) Kill na porta do SOCKS"
  echo -e "  3) Limpeza completa (stop xray + kill ambas)"
  echo -e "  0) Voltar"
  echo
  read -r -p "Escolha: " op
  case "$op" in
    1) kill_port "$PORT_TUNNEL"; echo -e "${GREEN}[OK] Kill tentado na porta ${PORT_TUNNEL}.${NC}"; pause ;;
    2) kill_port "$PORT_SOCKS"; echo -e "${GREEN}[OK] Kill tentado na porta ${PORT_SOCKS}.${NC}"; pause ;;
    3) force_cleanup_ports; pause ;;
    0) ;;
    *) echo "Inválido"; pause ;;
  esac
}

# =========================
# MAIN
# =========================
main() {
  require_root
  load_settings
  ensure_uuid
  ensure_deps
  load_sites

  local VPS_IP
  VPS_IP="$(get_ip)"

  # Vistoria assim que entra no menu (se habilitado)
  if [[ "${AUTO_AUDIT_ON_START}" == "1" ]]; then
    audit_if_needed 1
  fi

  while true; do
    # Vistoria automática por intervalo
    audit_if_needed 0

    render_header "$VPS_IP"

    echo -e "${WHITE}Menu${NC}"
    echo -e "  1) ${GREEN}Instalar / Reparar${NC}        ${DIM}(regera config + limpa portas)${NC}"
    echo -e "  2) ${YELLOW}Alterar portas${NC}            ${DIM}(túnel / socks)${NC}"
    echo -e "  3) ${YELLOW}Alterar WS path${NC}"
    echo -e "  4) ${CYAN}Mostrar JSON do Windows${NC}    ${DIM}(Bridge)${NC}"
    echo -e "  5) ${CYAN}Diagnóstico completo${NC}"
    echo -e "  6) ${CYAN}Testar TODOS os sites agora${NC} ${DIM}(curl via SOCKS)${NC}"
    echo -e "  7) ${YELLOW}Port Doctor${NC}               ${DIM}(ver/kill porta presa)${NC}"
    echo -e "  8) ${CYAN}Reiniciar Xray${NC}"
    echo -e "  0) Sair"
    echo

    read -r -p "Escolha: " op
    case "$op" in
      1) install_or_repair ;;
      2) change_ports ;;
      3) change_ws_path ;;
      4) show_client_json "$VPS_IP" ;;
      5) diagnostico "$VPS_IP" ;;
      6) audit_all_sites; pause ;;
      7) port_doctor ;;
      8) restart_xray; echo -e "${GREEN}[OK] Reiniciado.${NC}"; pause ;;
      0) exit 0 ;;
      *) echo "Inválido"; pause ;;
    esac
  done
}

main "$@"
