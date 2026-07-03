#!/usr/bin/env bash
# =============================================================================
# XRAY TUNNEL MANAGER - Tunel reverso Portal (VPS) + Bridge (PC PMESP)
# Modos do mais disfarçado ao mais simples. compat = TESTADO e funcionou.
# =============================================================================
set -o pipefail
export TERM=${TERM:-xterm}

R=$'\033[0;31m'; G=$'\033[0;32m'; Y=$'\033[1;33m'; B=$'\033[0;34m'; C=$'\033[0;36m'; W=$'\033[1;37m'; D=$'\033[2m'; N=$'\033[0m'

UUID_F="/root/.xray_uuid"
PIN_F="/root/.xray_cert_pin"
MODE_F="/root/.xray_mode"
REALITY_F="/root/.xray_reality_keys"
CONFIG="/usr/local/etc/xray/config.json"
MODES="/root/xray_modes"
CERT="/usr/local/etc/xray"
LOG="/var/log/xray"
WIN="/root/COPIAR_PARA_TRABALHO"
XRAY="/usr/local/bin/xray"
SVC="xray"
SYNC="/root/vps_sync_restart.sh"

PORT=443; SOCKS=1080; DOMAIN="reverse.intranet"
WS="/tunnel"; XHTTP="/api/v3/sync"; FP="chrome"
REALITY_DEST="www.microsoft.com:443"; REALITY_SNI="www.microsoft.com"

# ordem: mais disfarçado -> mais normal
MODE_IDS=(ultra ghost vless_ws compat vless_tcp diag)

UUID=""; VPS_IP=""; PIN=""; MODE="compat"
REALITY_PRIV=""; REALITY_PUB=""; REALITY_SID=""

SITES=(
  "INTRANET|http://intranet.policiamilitar.sp.gov.br/"
  "COPOM|https://copomonline.policiamilitar.sp.gov.br/"
  "MURALHA|https://operacional.muralhapaulista.sp.gov.br/"
)

hr()  { printf '+%*s+\n' 76 '' | tr ' ' '-'; }
tit() { hr; echo -e "${B}${W}| $1${N}"; hr; }
sec() { echo -e "${W}| $1${N}"; printf '+%*s+\n' 76 '' | tr ' ' '-'; }
ask() { [[ -t 0 ]] && read -r -p "$1" _ </dev/tty || true; }

box_line() { printf '|%-74s|\n' " $1"; }

need_root() { [[ "${EUID:-$(id -u)}" -ne 0 ]] && { echo -e "${R}Execute como root.${N}"; exit 1; }; }

fix_lf_scripts() {
  local f
  for f in /root/xray.sh /root/vps_sync_restart.sh; do
    if [[ -f "$f" ]] && grep -q $'\r' "$f" 2>/dev/null; then
      sed -i 's/\r$//' "$f"
      echo -e "${Y}Corrigido CRLF em $f${N}"
    fi
  done
}

load() {
  [[ -f "$UUID_F" ]] && UUID=$(tr -d '[:space:]' < "$UUID_F")
  [[ -f "$PIN_F" ]] && PIN=$(tr -d '[:space:]' < "$PIN_F")
  [[ -f "$MODE_F" ]] && MODE=$(tr -d '[:space:]' < "$MODE_F")
  if [[ -f "$REALITY_F" ]]; then
    # shellcheck disable=SC1090
    source "$REALITY_F"
    REALITY_PRIV="${REALITY_PRIVATE_KEY:-}"
    REALITY_PUB="${REALITY_PUBLIC_KEY:-}"
    REALITY_SID="${REALITY_SHORT_ID:-}"
  fi
}

save_mode() { echo "$MODE" > "$MODE_F"; }

get_ip() {
  curl -4s --max-time 4 ifconfig.me 2>/dev/null || curl -4s --max-time 4 icanhazip.com 2>/dev/null || hostname -I | awk '{print $1}'
}

gen_uuid() { cat /proc/sys/kernel/random/uuid 2>/dev/null || "$XRAY" uuid 2>/dev/null || uuidgen; }

ensure_uuid() {
  [[ -n "$UUID" ]] && return 0
  UUID=$(gen_uuid); echo "$UUID" > "$UUID_F"
}

ensure_cert() {
  local cn="${VPS_IP:-127.0.0.1}"
  [[ -f "$CERT/cert.pem" ]] || openssl req -x509 -newkey rsa:2048 \
    -keyout "$CERT/key.pem" -out "$CERT/cert.pem" -days 3650 -nodes -subj "/CN=${cn}" >/dev/null 2>&1
  chmod 644 "$CERT/cert.pem"; chmod 640 "$CERT/key.pem"
  chown root:nogroup "$CERT/cert.pem" "$CERT/key.pem" 2>/dev/null || true
  PIN=$(openssl x509 -in "$CERT/cert.pem" -outform DER 2>/dev/null | openssl dgst -sha256 | awk '{print $2}')
  echo "$PIN" > "$PIN_F"
}

ensure_reality() {
  if [[ -n "$REALITY_PRIV" && -n "$REALITY_PUB" ]]; then return 0; fi
  local out priv pub sid
  out=$("$XRAY" x25519 2>/dev/null || true)
  priv=$(echo "$out" | awk '/PrivateKey:/ {print $2}')
  pub=$(echo "$out" | awk '/Password \(PublicKey\):/ {print $3}')
  [[ -z "$pub" ]] && pub=$(echo "$out" | awk '/Public key:/ {print $3}')
  sid=$(openssl rand -hex 8)
  [[ -z "$priv" || -z "$pub" ]] && return 1
  cat > "$REALITY_F" <<EOF
REALITY_PRIVATE_KEY='$priv'
REALITY_PUBLIC_KEY='$pub'
REALITY_SHORT_ID='$sid'
EOF
  REALITY_PRIV="$priv"; REALITY_PUB="$pub"; REALITY_SID="$sid"
}

mode_idx() { local i=0; for m in "${MODE_IDS[@]}"; do [[ "$m" == "$1" ]] && { echo "$i"; return 0; }; i=$((i+1)); done; return 1; }

mode_by_num() { [[ "$1" -ge 1 && "$1" -le ${#MODE_IDS[@]} ]] && echo "${MODE_IDS[$(( $1 - 1 ))]}"; }

mode_name() {
  case "$1" in
    ultra)    echo "ULTRA - REALITY + XHTTP (max disfarce)" ;;
    ghost)    echo "GHOST - XHTTP + TLS (alto disfarce)" ;;
    vless_ws) echo "VLESS_WS - WebSocket + TLS" ;;
    compat)   echo "COMPAT - VMess + WS + TLS [TESTADO OK]" ;;
    vless_tcp) echo "VLESS_TCP - TCP + TLS" ;;
    diag)     echo "DIAG - sem TLS (so teste rede)" ;;
    *) echo "$1" ;;
  esac
}

mode_desc() {
  case "$1" in
    ultra)    echo "Imita site real (Microsoft). Mais discreto. Pode falhar na PMESP." ;;
    ghost)    echo "Trafego parece HTTP/2 normal. Bom disfarce + estabilidade." ;;
    vless_ws) echo "VLESS com WebSocket. Meio-termo." ;;
    compat)   echo "FUNCIONOU no teste PMESP. Use se outros falharem." ;;
    vless_tcp) echo "TCP direto com TLS. Alternativa simples." ;;
    diag)     echo "Sem TLS - apenas diagnostico se WS e bloqueado." ;;
    *) echo "" ;;
  esac
}

prepare_mode() {
  case "$1" in
    ultra) ensure_reality ;;
    diag)  ;;
    *)     ensure_cert ;;
  esac
}

portal_in() {
  local m="$1"
  case "$m" in
    compat)
      cat <<EOF
    { "tag":"tunnel-in","port":$PORT,"protocol":"vmess",
      "settings":{"clients":[{"id":"$UUID"}]},
      "streamSettings":{"network":"ws","security":"tls",
        "tlsSettings":{"certificates":[{"certificateFile":"$CERT/cert.pem","keyFile":"$CERT/key.pem"}]},
        "wsSettings":{"path":"$WS"}} }
EOF
      ;;
    ghost)
      cat <<EOF
    { "tag":"tunnel-in","port":$PORT,"protocol":"vless",
      "settings":{"clients":[{"id":"$UUID","decryption":"none"}]},
      "streamSettings":{"network":"xhttp","security":"tls",
        "tlsSettings":{"certificates":[{"certificateFile":"$CERT/cert.pem","keyFile":"$CERT/key.pem"}]},
        "xhttpSettings":{"path":"$XHTTP","mode":"auto"}} }
EOF
      ;;
    ultra)
      cat <<EOF
    { "tag":"tunnel-in","port":$PORT,"protocol":"vless",
      "settings":{"clients":[{"id":"$UUID","decryption":"none"}]},
      "streamSettings":{"network":"xhttp","security":"reality",
        "realitySettings":{"show":false,"dest":"$REALITY_DEST","xver":0,
          "serverNames":["$REALITY_SNI"],"fingerprint":"$FP",
          "privateKey":"$REALITY_PRIV","shortIds":["","$REALITY_SID"]},
        "xhttpSettings":{"path":"$XHTTP","mode":"auto"}} }
EOF
      ;;
    vless_ws)
      cat <<EOF
    { "tag":"tunnel-in","port":$PORT,"protocol":"vless",
      "settings":{"clients":[{"id":"$UUID","decryption":"none"}]},
      "streamSettings":{"network":"ws","security":"tls",
        "tlsSettings":{"certificates":[{"certificateFile":"$CERT/cert.pem","keyFile":"$CERT/key.pem"}]},
        "wsSettings":{"path":"$WS"}} }
EOF
      ;;
    vless_tcp)
      cat <<EOF
    { "tag":"tunnel-in","port":$PORT,"protocol":"vless",
      "settings":{"clients":[{"id":"$UUID","decryption":"none"}]},
      "streamSettings":{"network":"tcp","security":"tls",
        "tlsSettings":{"certificates":[{"certificateFile":"$CERT/cert.pem","keyFile":"$CERT/key.pem"}]}} }
EOF
      ;;
    diag)
      cat <<EOF
    { "tag":"tunnel-in","port":$PORT,"protocol":"vmess",
      "settings":{"clients":[{"id":"$UUID"}]},
      "streamSettings":{"network":"ws","wsSettings":{"path":"$WS"}} }
EOF
      ;;
  esac
}

bridge_out() {
  local m="$1" ip="$2"
  case "$m" in
    compat)
      cat <<EOF
    { "tag":"tunnel-out","protocol":"vmess",
      "settings":{"vnext":[{"address":"$ip","port":$PORT,"users":[{"id":"$UUID","security":"auto"}]}]},
      "streamSettings":{"network":"ws","security":"tls",
        "tlsSettings":{"serverName":"$ip","pinnedPeerCertSha256":"$PIN"},
        "wsSettings":{"path":"$WS"}} }
EOF
      ;;
    ghost)
      cat <<EOF
    { "tag":"tunnel-out","protocol":"vless",
      "settings":{"vnext":[{"address":"$ip","port":$PORT,"users":[{"id":"$UUID","encryption":"none"}]}]},
      "streamSettings":{"network":"xhttp","security":"tls",
        "tlsSettings":{"serverName":"$ip","fingerprint":"$FP","pinnedPeerCertSha256":"$PIN"},
        "xhttpSettings":{"path":"$XHTTP","mode":"auto"}} }
EOF
      ;;
    vless_ws)
      cat <<EOF
    { "tag":"tunnel-out","protocol":"vless",
      "settings":{"vnext":[{"address":"$ip","port":$PORT,"users":[{"id":"$UUID","encryption":"none"}]}]},
      "streamSettings":{"network":"ws","security":"tls",
        "tlsSettings":{"serverName":"$ip","fingerprint":"$FP","pinnedPeerCertSha256":"$PIN"},
        "wsSettings":{"path":"$WS"}} }
EOF
      ;;
    ultra)
      cat <<EOF
    { "tag":"tunnel-out","protocol":"vless",
      "settings":{"vnext":[{"address":"$ip","port":$PORT,"users":[{"id":"$UUID","encryption":"none"}]}]},
      "streamSettings":{"network":"xhttp","security":"reality",
        "realitySettings":{"fingerprint":"$FP","serverName":"$REALITY_SNI",
          "publicKey":"$REALITY_PUB","shortId":"$REALITY_SID","spiderX":"/"},
        "xhttpSettings":{"path":"$XHTTP","mode":"auto"}} }
EOF
      ;;
    vless_tcp)
      cat <<EOF
    { "tag":"tunnel-out","protocol":"vless",
      "settings":{"vnext":[{"address":"$ip","port":$PORT,"users":[{"id":"$UUID","encryption":"none"}]}]},
      "streamSettings":{"network":"tcp","security":"tls",
        "tlsSettings":{"serverName":"$ip","fingerprint":"$FP","pinnedPeerCertSha256":"$PIN"}} }
EOF
      ;;
    diag)
      cat <<EOF
    { "tag":"tunnel-out","protocol":"vmess",
      "settings":{"vnext":[{"address":"$ip","port":$PORT,"users":[{"id":"$UUID","security":"auto"}]}]},
      "streamSettings":{"network":"ws","wsSettings":{"path":"$WS"}} }
EOF
      ;;
  esac
}

write_portal() {
  local m="$1" dest="${2:-$CONFIG}" tmp="${dest}.tmp"
  prepare_mode "$m" || return 1
  portal_in "$m" > /tmp/.pin
  cat > "$tmp" <<EOF
{
  "log":{"loglevel":"warning","access":"$LOG/access.log","error":"$LOG/error.log"},
  "reverse":{"portals":[{"tag":"portal","domain":"$DOMAIN"}]},
  "inbounds":[
    {"tag":"socks","listen":"127.0.0.1","port":$SOCKS,"protocol":"socks",
     "settings":{"auth":"noauth","udp":true},
     "sniffing":{"enabled":true,"destOverride":["http","tls"]}},
$(cat /tmp/.pin)
  ],
  "routing":{"rules":[
    {"type":"field","inboundTag":["socks"],"outboundTag":"portal"},
    {"type":"field","inboundTag":["tunnel-in"],"outboundTag":"portal"}
  ]}
}
EOF
  jq empty "$tmp" >/dev/null 2>&1 || { rm -f "$tmp"; echo -e "${R}Portal JSON invalido${N}"; return 1; }
  [[ "$dest" == "$CONFIG" ]] && cp "$CONFIG" "${CONFIG}.bak" 2>/dev/null || true
  mv "$tmp" "$dest"
}

write_bridge() {
  local m="$1" out="$2"
  prepare_mode "$m" || return 1
  bridge_out "$m" "$VPS_IP" > /tmp/.bout
  cat > "$out" <<EOF
{
  "log":{"loglevel":"warning"},
  "reverse":{"bridges":[{"tag":"bridge","domain":"$DOMAIN"}]},
  "outbounds":[
$(cat /tmp/.bout),
    {"tag":"out","protocol":"freedom","settings":{"domainStrategy":"UseIP"}}
  ],
  "routing":{"rules":[
    {"type":"field","domain":["full:$DOMAIN"],"outboundTag":"tunnel-out"},
    {"type":"field","inboundTag":["bridge"],"outboundTag":"out"}
  ]}
}
EOF
  jq empty "$out" >/dev/null 2>&1
}

mode_valid() {
  local m="$1" x
  for x in "${MODE_IDS[@]}"; do [[ "$x" == "$m" ]] && return 0; done
  return 1
}

apply_mode() {
  local m="$1"
  MODE="$m"
  VPS_IP=$(get_ip)
  [[ -z "$UUID" ]] && ensure_uuid
  write_portal "$m" || return 1
  mkdir -p "$MODES" "$WIN/bin"
  write_bridge "$m" "$MODES/${m}.json" || return 1
  write_bridge "$m" "$WIN/config.json" || return 1
  cp "$WIN/config.json" "$WIN/config_${m}.json"
  chmod 644 "$WIN/config.json" "$WIN/config_${m}.json" 2>/dev/null || true
  save_mode
  echo -e "${C}  config.json -> $WIN/config.json${N}"
  if [[ ! -x "$XRAY" ]]; then
    echo -e "${Y}  Xray ainda nao instalado - config gerado, rode opcao 1${N}"
    return 0
  fi
  "$XRAY" run -test -config "$CONFIG" >/dev/null 2>&1 || { echo -e "${R}Teste portal FAIL${N}"; return 1; }
  "$XRAY" run -test -config "$WIN/config.json" >/dev/null 2>&1 || { echo -e "${R}Teste bridge FAIL${N}"; return 1; }
  systemctl restart "$SVC" 2>/dev/null; sleep 2
  if systemctl is-active --quiet "$SVC" 2>/dev/null; then
    echo -e "${G}[OK] $(mode_name "$m") ATIVO na VPS${N}"
    echo
    box_line "PROXIMO: copie config.json -> PC -> INICIAR.bat -> sync"
    box_line "UUID: $UUID"
    [[ "$m" != "ultra" && "$m" != "diag" ]] && box_line "PIN:  $PIN"
  else
    echo -e "${Y}Portal/config gerados. Xray off - rode: systemctl start xray${N}"
    journalctl -u "$SVC" -n 5 --no-pager 2>/dev/null || true
  fi
}

test_mode_json() {
  local m="$1" pt="/tmp/portal_test_${m}.json"
  tit "TESTE JSON: $(mode_name "$m")"
  prepare_mode "$m" || return 1
  write_portal "$m" "$pt" || return 1
  write_bridge "$m" "$MODES/${m}.json" || return 1
  echo -n "  Portal... "
  if "$XRAY" run -test -config "$pt" >/dev/null 2>&1; then echo -e "${G}OK${N}"; else echo -e "${R}FAIL${N}"; rm -f "$pt"; return 1; fi
  echo -n "  Bridge... "
  if "$XRAY" run -test -config "$MODES/${m}.json" >/dev/null 2>&1; then echo -e "${G}OK${N}"; else echo -e "${R}FAIL${N}"; rm -f "$pt"; return 1; fi
  rm -f "$pt"
  write_bridge "$m" "$WIN/config_${m}.json" || true
  echo -e "${Y}  Portal em producao NAO foi alterado.${N}"
  echo -e "  Para ativar: menu op 2 ou bash /root/xray.sh --mode $m"
  return 0
}

test_all_json() {
  local m ok=0 fail=0
  for m in "${MODE_IDS[@]}"; do
    test_mode_json "$m" && ok=$((ok+1)) || fail=$((fail+1))
    echo
  done
  echo "Resultado: $ok OK / $fail FAIL"
  ask "Enter..."
}

gen_win_one() {
  local m="$1"
  prepare_mode "$m" || return 1
  write_bridge "$m" "$WIN/config_${m}.json" || return 1
  echo -e "${G}Gerado: $WIN/config_${m}.json${N}"
  [[ "$m" == "$MODE" ]] && cp "$WIN/config_${m}.json" "$WIN/config.json"
}

vistoria() {
  tit "VISTORIA INTRANET (via SOCKS)"
  local item n u code
  for item in "${SITES[@]}"; do
    n="${item%%|*}"; u="${item#*|}"
    code=$(curl -sS -o /dev/null -w '%{http_code}' --connect-timeout 8 --max-time 20 \
      --proxy socks5h://127.0.0.1:$SOCKS -k "$u" 2>/dev/null || echo 000)
    if [[ "$code" == "200" || "$code" == "301" || "$code" == "302" ]]; then
      echo -e "  ${G}$n HTTP $code OK${N}"
    else
      echo -e "  ${R}$n HTTP $code FALHOU${N}"
    fi
  done
  ask "Enter..."
}

show_status() {
  local n bmode cfgst
  bmode=$(mode_name "$MODE")
  n=$(ss -Htn state established '( sport = :'"$PORT"' )' 2>/dev/null | wc -l | tr -d ' ')
  if [[ -f "$WIN/config.json" ]]; then cfgst="${G}config.json OK${N}"; else cfgst="${R}config.json FALTA${N}"; fi
  sec "PAINEL"
  box_line "Modo:   $bmode"
  box_line "IP:     $VPS_IP"
  box_line "UUID:   ${UUID:-nao gerado}"
  box_line "Bridge: ${n} tcp :443"
  systemctl is-active --quiet "$SVC" 2>/dev/null && box_line "Xray:   ONLINE" || box_line "Xray:   OFFLINE"
  box_line "Win:    $cfgst"
  box_line "SOCKS:  127.0.0.1:$SOCKS"
}

diag() {
  tit "DIAGNOSTICO"
  show_status
  echo
  ss -Hltnp "sport = :$PORT" 2>/dev/null || true
  echo "--- error log ---"
  tail -8 "$LOG/error.log" 2>/dev/null || true
  ask "Enter..."
}

install_all() {
  tit "INSTALACAO COMPLETA"
  fix_lf_scripts
  box_line "Passo 1/5: pacotes..."
  apt-get update -y >/dev/null 2>&1 || true
  apt-get install -y curl jq openssl net-tools ca-certificates >/dev/null 2>&1 || true
  mkdir -p "$CERT" "$LOG" "$MODES" "$WIN/bin"
  touch "$LOG/access.log" "$LOG/error.log"
  chown nobody:nogroup "$LOG/access.log" "$LOG/error.log" 2>/dev/null || chown nobody "$LOG/access.log" "$LOG/error.log" 2>/dev/null || true
  chmod 644 "$LOG/access.log" "$LOG/error.log" 2>/dev/null || true
  VPS_IP=$(get_ip)
  ensure_uuid; ensure_cert
  box_line "Passo 2/5: Xray..."
  bash -c "$(curl -fsSL https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install
  setcap CAP_NET_BIND_SERVICE=+eip "$XRAY" 2>/dev/null || true
  chown -R nobody:nogroup "$LOG" 2>/dev/null || true
  ensure_reality || true
  systemctl enable "$SVC" >/dev/null 2>&1 || true
  cp /root/vps_sync_restart.sh "$SYNC" 2>/dev/null || true
  chmod +x "$SYNC" /root/xray.sh 2>/dev/null || true
  fix_lf_scripts
  box_line "Passo 3/5: modo COMPAT [TESTADO]..."
  apply_mode compat || { echo -e "${R}Falha apply compat${N}"; return 1; }
  box_line "Passo 4/5: todos config_*.json..."
  local m
  for m in "${MODE_IDS[@]}"; do gen_win_one "$m" 2>/dev/null || true; done
  cp "$WIN/config_compat.json" "$WIN/config.json" 2>/dev/null || true
  write_help_win
  box_line "Passo 5/5: testes JSON..."
  local ok=0 fail=0 m pt
  for m in "${MODE_IDS[@]}"; do
    pt="/tmp/p_${m}.json"
    if prepare_mode "$m" && write_portal "$m" "$pt" && write_bridge "$m" "$MODES/${m}.json"; then
      if "$XRAY" run -test -config "$pt" >/dev/null 2>&1 && "$XRAY" run -test -config "$MODES/${m}.json" >/dev/null 2>&1; then
        ok=$((ok+1))
      else
        fail=$((fail+1))
      fi
    else
      fail=$((fail+1))
    fi
    rm -f "$pt"
  done
  echo
  echo -e "${G}Instalacao OK${N} | JSON testes: $ok ok / $fail fail"
  ls -la "$WIN/config.json" "$WIN/config_compat.json" 2>/dev/null || true
  ask "Enter..."
}

write_help_win() {
  cat > "$WIN/LEIA-ME.txt" <<'EOF'
TUNEL REVERSO PMESP
===================

FLUXO (sempre nesta ordem):
  1) VPS: escolha o modo no menu (comecar com compat = TESTADO)
  2) Copie config.json desta pasta para C:\tun2socks\COPIAR_PARA_TRABALHO\
  3) PC trabalho: INICIAR.bat (deixe a janela aberta)
  4) VPS: bash /root/vps_sync_restart.sh

MODOS (do mais disfarçado ao normal):
  ultra     REALITY - max disfarce
  ghost     XHTTP+TLS - alto disfarce
  vless_ws  VLESS WebSocket
  compat    TESTADO - funcionou na PMESP
  vless_tcp TCP direto
  diag      sem TLS - so diagnostico

Se um modo falhar no PC: volte para compat no menu VPS.
EOF
}

menu_modes() {
  local i=1 m op yn
  while true; do
    clear; tit "ATIVAR MODO"
    echo -e "${Y}Ativa portal VPS + gera config.json para o Windows.${N}"
    echo -e "${Y}VPS e PC precisam do MESMO modo.${N}"
    echo
    for m in "${MODE_IDS[@]}"; do
      [[ "$m" == "compat" ]] && tag="${G}[TESTADO]${N}" || tag=""
      printf "  %d  %-10s %s\n" "$i" "$m" "$(mode_name "$m")"
      echo -e "      ${D}$(mode_desc "$m")${N}"
      i=$((i+1))
    done
    echo "  0  voltar"
    read -r -p "Escolha: " op </dev/tty
    [[ "$op" == "0" ]] && return 0
    m=$(mode_by_num "$op")
    [[ -z "$m" ]] && { echo "Invalido"; sleep 1; continue; }
    apply_mode "$m"
    ask "Enter..."
  done
}

menu_lab() {
  local i=1 m op
  while true; do
    clear; tit "LABORATORIO"
    echo "  Testa JSON sem alterar o portal em producao."
    echo
    for m in "${MODE_IDS[@]}"; do
      printf "  %d  %s\n" "$i" "$(mode_name "$m")"
      i=$((i+1))
    done
    echo "  A  testar TODOS"
    echo "  0  voltar"
    read -r -p "Escolha: " op </dev/tty
    [[ "$op" == "0" ]] && return 0
    [[ "$op" == "A" || "$op" == "a" ]] && { test_all_json; continue; }
    m=$(mode_by_num "$op")
    [[ -z "$m" ]] && { echo "Invalido"; sleep 1; continue; }
    test_mode_json "$m"
    read -r -p "Ativar este modo agora? s/N: " yn </dev/tty
    [[ "$yn" == "s" || "$yn" == "S" ]] && apply_mode "$m"
    ask "Enter..."
  done
}

menu_gen_win() {
  clear; tit "GERAR CONFIG WINDOWS"
  echo "  1  config.json (modo ATIVO: $MODE)"
  echo "  2  um modo especifico"
  echo "  3  todos config_*.json"
  echo "  0  voltar"
  read -r -p "Escolha: " op </dev/tty
  case "$op" in
    0) return 0 ;;
    1) gen_win_one "$MODE"; cp "$WIN/config_${MODE}.json" "$WIN/config.json" 2>/dev/null || write_bridge "$MODE" "$WIN/config.json" ;;
    2)
      local i=1 m
      for m in "${MODE_IDS[@]}"; do
        printf "  %d %s\n" "$i" "$m"
        i=$((i+1))
      done
      read -r -p "Numero: " op </dev/tty
      m=$(mode_by_num "$op"); [[ -n "$m" ]] && gen_win_one "$m"
      ;;
    3)
      for m in "${MODE_IDS[@]}"; do gen_win_one "$m" || true; done
      cp "$WIN/config_${MODE}.json" "$WIN/config.json" 2>/dev/null || true
      ;;
  esac
  ask "Enter..."
}

menu_help() {
  clear; tit "COMO USAR"
  cat <<'EOF'
  VPS NOVA:
    Opcao 1 = Instalar (modo compat TESTADO)

  TUNEL FUNCIONANDO:
    1) Menu op 2 -> escolha modo (compat primeiro)
    2) Copie /root/COPIAR_PARA_TRABALHO/config.json -> PC
    3) PC: INICIAR.bat (janela aberta)
    4) VPS: bash /root/vps_sync_restart.sh
    5) Menu op 5 = vistoria intranet

  TESTAR OUTRO MODO SEM MUDAR VPS:
    Menu op 3 (lab) ou --gen-config ghost

  SE FALHAR:
    Menu op 2 -> compat [TESTADO]

  ATALHOS:
    bash /root/xray.sh --install
    bash /root/xray.sh --mode compat
    bash /root/xray.sh --mode ghost
    bash /root/vps_sync_restart.sh
EOF
  ask "Enter..."
}

main_menu() {
  while true; do
    clear
    tit "XRAY TUNNEL MANAGER  v2.0"
    show_status
    echo
    sec "MENU PRINCIPAL"
    box_line "1  Instalar / Reparar (VPS nova)"
    box_line "2  Ativar modo (portal + config.json)"
    box_line "3  Laboratorio (testar JSON)"
    box_line "4  Gerar config Windows"
    box_line "5  Vistoria intranet PMESP"
    box_line "6  Sync restart (pos INICIAR.bat)"
    box_line "7  Diagnostico"
    box_line "8  Ajuda passo a passo"
    box_line "0  Sair"
    echo
    read -r -p "Opcao: " op </dev/tty
    case "$op" in
      1) install_all ;;
      2) menu_modes ;;
      3) menu_lab ;;
      4) menu_gen_win ;;
      5) vistoria ;;
      6) bash "$SYNC" 2>/dev/null || echo "Falta $SYNC"; ask "Enter..." ;;
      7) diag ;;
      8) menu_help ;;
      0) exit 0 ;;
      *) echo "Invalido"; sleep 1 ;;
    esac
  done
}

main() {
  need_root
  fix_lf_scripts
  load
  VPS_IP=$(get_ip)
  [[ -z "$UUID" ]] && ensure_uuid
  case "${1:-}" in
    --fix-lf) fix_lf_scripts; exit 0 ;;
    --install) install_all; exit 0 ;;
    --mode)
      m="${2:-}"
      mode_valid "$m" || { echo "Modos: ultra ghost vless_ws compat vless_tcp diag"; exit 1; }
      apply_mode "$m" || exit 1; exit 0 ;;
    --gen-config)
      m="${2:-}"
      mode_valid "$m" || { echo "Modos: ultra ghost vless_ws compat vless_tcp diag"; exit 1; }
      gen_win_one "$m" || exit 1; exit 0 ;;
    --test-all) test_all_json; exit 0 ;;
    --sync) bash "$SYNC"; exit 0 ;;
  esac
  main_menu
}

main "$@"
