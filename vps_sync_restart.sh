#!/usr/bin/env bash
set -o pipefail
export TERM=${TERM:-xterm}

SVC="xray"
MODE_F="/root/.xray_mode"
ERR="/var/log/xray/error.log"
G=$'\033[0;32m'; R=$'\033[0;31m'; Y=$'\033[1;33m'; N=$'\033[0m'

need_root() { [[ "${EUID:-$(id -u)}" -ne 0 ]] || return 0; echo "Rode como root"; exit 1; }

MODE="compat"
[[ -f "$MODE_F" ]] && MODE=$(tr -d '[:space:]' < "$MODE_F")

echo "=========================================="
echo " SYNC RESTART PORTAL"
echo " Modo VPS: $MODE"
echo " PC deve usar config.json do MESMO modo"
echo "=========================================="
echo

need_root

systemctl stop "$SVC" 2>/dev/null || true
sleep 2

echo "[1/3] Aguardando 15s (bridge INICIAR.bat no Windows)..."
sleep 15

systemctl start "$SVC"
sleep 3

systemctl is-active --quiet "$SVC" || {
  echo -e "${R}xray nao subiu${N}"
  journalctl -u "$SVC" -n 10 --no-pager
  exit 1
}

N=$(ss -Htn state established '( sport = :443 )' 2>/dev/null | wc -l | tr -d ' ')
echo "[2/3] Conexoes bridge TCP :443 = $N"

if [[ "$N" == "0" ]]; then
  echo -e "${R}NENHUM bridge conectado.${N}"
  echo
  echo "Checklist:"
  echo "  [ ] VPS modo $MODE ativo (menu op 2)"
  echo "  [ ] config.json copiado da VPS pro PC"
  echo "  [ ] INICIAR.bat rodando (janela aberta)"
  echo "  [ ] Se falhou: bash /root/xray.sh --mode compat"
  tail -4 "$ERR" 2>/dev/null || true
  exit 2
fi

CODE=$(curl -sS -o /dev/null -w '%{http_code}' --connect-timeout 10 --max-time 25 \
  --proxy socks5h://127.0.0.1:1080 -k https://www.google.com/ 2>/dev/null || echo 000)
echo "[3/3] Teste SOCKS google: HTTP $CODE"

if grep -q "empty worker list" "$ERR" 2>/dev/null; then
  echo -e "${R}empty worker list - bridge nao registrou${N}"
  exit 2
fi

if [[ "$CODE" == "200" || "$CODE" == "301" || "$CODE" == "302" ]]; then
  echo -e "${G}TUNEL OK - pode usar SOCKS 127.0.0.1:1080 na VPS${N}"
  exit 0
fi

echo -e "${Y}Bridge conectou mas SOCKS falhou - rode menu vistoria${N}"
exit 3
