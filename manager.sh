#!/bin/bash
# ==================================================================
#  PMESP MANAGER ULTIMATE V8.0 - TÁTICO INTEGRADO (VERSÃO TOTAL)
# ==================================================================

# --- ARQUIVOS DE DADOS ---
DB_PMESP="/etc/pmesp_users.json"
DB_CHAMADOS="/etc/pmesp_tickets.json"
CONFIG_SMTP="/etc/msmtprc"
LOG_MONITOR="/var/log/pmesp_monitor.log"

# Garante arquivos básicos e limpa linhas vazias
[ ! -f "$DB_PMESP" ] && touch "$DB_PMESP" && chmod 666 "$DB_PMESP"
[ ! -f "$DB_CHAMADOS" ] && touch "$DB_CHAMADOS" && chmod 666 "$DB_CHAMADOS"
[ ! -f "$LOG_MONITOR" ] && touch "$LOG_MONITOR" && chmod 644 "$LOG_MONITOR"

# --- CORES ---
R="\033[1;31m"; G="\033[1;32m"; Y="\033[1;33m"; B="\033[1;34m"
P="\033[1;35m"; C="\033[1;36m"; W="\033[1;37m"; NC="\033[0m"
LINE_H="${C}═${NC}"

# --- FUNÇÕES VISUAIS ---

cabecalho() {
    clear
    # Conta objetos JSON reais no arquivo de forma segura
    _tuser=$(jq -s 'length' "$DB_PMESP" 2>/dev/null || echo "0")
    _ons=$(who | grep -v 'root' | wc -l)
    _ip=$(wget -qO- ipv4.icanhazip.com 2>/dev/null || echo "N/A")

    echo -e "${C}╭${LINE_H}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${C}╮${NC}"
    echo -e "${C}┃${P}           PMESP MANAGER V8.0 - TÁTICO INTEGRADO           ${C}┃${NC}"
    echo -e "${C}┣${LINE_H}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┫${NC}"
    echo -e "${C}┃ ${Y}TOTAL: ${W}$_tuser ${Y}| ONLINE: ${G}$_ons ${Y}| IP: ${G}$_ip${C}   ┃${NC}"
    echo -e "${C}┗${LINE_H}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛${NC}"
}

barra() { echo -e "${C}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"; }

# --- GESTÃO DE USUÁRIOS (01 a 08) ---

criar_usuario() {
    cabecalho
    echo -e "${G}>>> NOVO CADASTRO DE POLICIAL${NC}"
    read -p "Matrícula (RE): " matricula
    read -p "Email: " email
    read -p "Login: " usuario
    [ -z "$usuario" ] && return
    
    if id "$usuario" >/dev/null 2>&1; then 
        echo -e "\n${R}ERRO: Usuário já existe!${NC}"
        sleep 2; return
    fi

    read -p "Senha Provisória: " senha
    read -p "Validade (Dias): " dias
    read -p "Limite de Telas: " limite

    useradd -M -s /bin/false "$usuario"
    echo "$usuario:$senha" | chpasswd
    data_exp=$(date -d "+$dias days" +"%Y-%m-%d")
    chage -E "$data_exp" "$usuario"

    item=$(jq -c -n --arg u "$usuario" --arg s "$senha" --arg d "$dias" --arg l "$limite" \
        --arg m "$matricula" --arg e "$email" --arg h "PENDENTE" --arg ex "$data_exp" \
        '{usuario: $u, senha: $s, dias: $d, limite: $l, matricula: $m, email: $e, hwid: $h, expiracao: $ex}')
    
    echo "$item" >> "$DB_PMESP"
    echo -e "\n${G}Usuário $usuario criado com sucesso!${NC}"
    sleep 2
}

listar_usuarios() {
    cabecalho
    echo -e "${C}>>> LISTA DE USUÁRIOS CADASTRADOS${NC}"
    barra
    printf "${W}%-12s | %-10s | %-11s | %-4s | %-10s${NC}\n" "USUÁRIO" "RE" "EXPIRA" "LIM" "HWID"
    barra
    
    if [ -s "$DB_PMESP" ]; then
        # jq -c transforma qualquer JSON em uma linha única para o loop
        jq -c '.' "$DB_PMESP" 2>/dev/null | while read -r line; do
            u=$(echo "$line" | jq -r .usuario); m=$(echo "$line" | jq -r .matricula)
            ex=$(echo "$line" | jq -r .expiracao); l=$(echo "$line" | jq -r .limite)
            h=$(echo "$line" | jq -r .hwid)
            printf "${Y}%-12s${NC} | %-10s | %-11s | %-4s | %-10s\n" "$u" "$m" "$ex" "$l" "${h:0:10}"
        done
    else
        echo -e "${R}Nenhum usuário cadastrado.${NC}"
    fi
    echo ""
    read -p "Pressione Enter para voltar..."
}

remover_usuario_direto() {
    cabecalho
    read -p "Login para remover: " user_alvo
    if id "$user_alvo" >/dev/null 2>&1; then
        userdel -f "$user_alvo"
        tmp=$(mktemp)
        jq -c "select(.usuario != \"$user_alvo\")" "$DB_PMESP" > "$tmp"
        mv "$tmp" "$DB_PMESP"
        echo -e "${G}Removido!${NC}"
    else
        echo -e "${R}Não encontrado.${NC}"
    fi
    sleep 2
}

alterar_validade_direto() {
    cabecalho
    read -p "Login: " user_alvo
    read -p "Novos dias: " novos_dias
    if id "$user_alvo" >/dev/null 2>&1; then
        nova_data=$(date -d "+$novos_dias days" +"%Y-%m-%d")
        chage -E "$nova_data" "$user_alvo"
        tmp=$(mktemp)
        jq -c "if .usuario == \"$user_alvo\" then .expiracao = \"$nova_data\" | .dias = \"$novos_dias\" else . end" "$DB_PMESP" > "$tmp"
        mv "$tmp" "$DB_PMESP"
        echo -e "${G}Validade: $nova_data${NC}"
    fi
    sleep 2
}

usuarios_vencidos() {
    cabecalho
    echo -e "${R}>>> USUÁRIOS VENCIDOS OU PRÓXIMOS (7 DIAS)${NC}"
    barra
    today=$(date +%s)
    jq -c '.' "$DB_PMESP" 2>/dev/null | while read -r line; do
        u=$(echo "$line" | jq -r .usuario); ex=$(echo "$line" | jq -r .expiracao)
        exp_sec=$(date -d "$ex" +%s 2>/dev/null)
        if [ "$exp_sec" -lt "$today" ]; then
            echo -e "${R}$u - EXPIRADO EM $ex${NC}"
        fi
    done
    read -p "Enter..."
}

mostrar_usuarios_online() {
    tput civis; trap 'tput cnorm; return' SIGINT
    while true; do
        cabecalho
        echo -e "${C}>>> MONITORAMENTO ONLINE (CTRL+C Sair)${NC}"
        barra
        active=0
        jq -c '.' "$DB_PMESP" 2>/dev/null | while read -r line; do
            u=$(echo "$line" | jq -r .usuario); l=$(echo "$line" | jq -r .limite)
            s=$(who | grep -w "$u" | wc -l)
            if [ "$s" -gt 0 ]; then
                printf "${Y}%-15s${NC} | %-10s | %-6s\n" "$u" "$s" "$l"
                active=$((active+1))
            fi
        done
        sleep 2
    done
}

recuperar_senha() {
    cabecalho
    read -p "Usuário: " user_alvo
    email_dest=$(jq -r "select(.usuario==\"$user_alvo\") | .email" "$DB_PMESP")
    if [ ! -z "$email_dest" ]; then
        nova=$(tr -dc A-Za-z0-9 </dev/urandom | head -c 8)
        echo "$user_alvo:$nova" | chpasswd
        echo -e "Subject: Nova Senha PMESP\n\nSenha: $nova" | msmtp "$email_dest"
        echo -e "${G}Senha enviada!${NC}"
    fi
    read -p "Enter..."
}

atualizar_hwid() {
    cabecalho
    read -p "Usuário: " u; read -p "Novo HWID: " h
    tmp=$(mktemp)
    jq -c "if .usuario == \"$u\" then .hwid = \"$h\" else . end" "$DB_PMESP" > "$tmp"
    mv "$tmp" "$DB_PMESP"
    echo -e "${G}HWID Atualizado!${NC}"; sleep 2
}

# --- SUPORTE E SISTEMA (09 a 15) ---

novo_chamado() {
    cabecalho
    ID=$((1000 + RANDOM % 8999))
    read -p "Login: " u; read -p "Problema: " p
    jq -n --arg i "$ID" --arg u "$u" --arg p "$p" --arg s "ABERTO" --arg d "$(date)" \
    '{id: $i, usuario: $u, problema: $p, status: $s, data: $d}' >> "$DB_CHAMADOS"
    echo -e "${G}Chamado #$ID criado.${NC}"; sleep 2
}

gerenciar_chamados() {
    cabecalho
    [ -s "$DB_CHAMADOS" ] && cat "$DB_CHAMADOS" | jq -r '"ID: \(.id) | USER: \(.usuario) | STATUS: \(.status)"'
    read -p "Enter..."
}

configurar_smtp() {
    cabecalho
    read -p "Gmail: " e; read -p "Senha App: " s
    cat <<EOF > "$CONFIG_SMTP"
defaults
auth on
tls on
tls_trust_file /etc/ssl/certs/ca-certificates.crt
account gmail
host smtp.gmail.com
port 587
from $e
user $e
password $s
account default : gmail
EOF
    echo -e "${G}SMTP OK!${NC}"; sleep 2
}

install_deps() {
    cabecalho
    apt update && apt install jq msmtp net-tools squid sslh -y
    echo -e "${G}Instalado!${NC}"; sleep 2
}

install_squid() {
    cabecalho; apt install squid -y >/dev/null
    echo "http_port 3128" > /etc/squid/squid.conf
    echo "acl all src 0.0.0.0/0" >> /etc/squid/squid.conf
    echo "http_access allow all" >> /etc/squid/squid.conf
    systemctl restart squid; echo -e "${G}Squid On 3128!${NC}"; sleep 2
}

install_sslh() {
    cabecalho; apt install sslh -y >/dev/null
    echo 'DAEMON_OPTS="--user sslh --listen 0.0.0.0:443 --ssh 127.0.0.1:22"' > /etc/default/sslh
    systemctl restart sslh; echo -e "${G}SSLH On 443!${NC}"; sleep 2
}

configurar_cron_monitor() {
    cabecalho
    p=$(readlink -f "$0")
    (crontab -l 2>/dev/null | grep -v "cron-monitor"; echo "*/1 * * * * /bin/bash $p --cron-monitor >/dev/null 2>&1") | crontab -
    echo -e "${G}Cron Ativado!${NC}"; sleep 2
}

# --- MENU ---

menu() {
    while true; do
        cabecalho
        echo -e "${C}┃ ${G}01${W} ⮞ CRIAR USUÁRIO           ${C}┃ ${G}09${W} ⮞ NOVO CHAMADO${NC}"
        echo -e "${C}┃ ${G}02${W} ⮞ LISTAR USUÁRIOS          ${C}┃ ${G}10${W} ⮞ GERENCIAR CHAMADOS${NC}"
        echo -e "${C}┃ ${G}03${W} ⮞ REMOVER USUÁRIO          ${C}┃ ${G}11${W} ⮞ CONFIGURAR SMTP${NC}"
        echo -e "${C}┃ ${G}04${W} ⮞ ALTERAR VALIDADE         ${C}┃ ${G}12${W} ⮞ INSTALAR DEPS${NC}"
        echo -e "${C}┃ ${G}05${W} ⮞ USUÁRIOS VENCIDOS        ${C}┃ ${G}13${W} ⮞ INSTALAR SQUID${NC}"
        echo -e "${C}┃ ${G}06${W} ⮞ MONITOR ONLINE           ${C}┃ ${G}14${W} ⮞ INSTALAR SSLH${NC}"
        echo -e "${C}┃ ${G}07${W} ⮞ RESET SENHA (EMAIL)      ${C}┃ ${G}15${W} ⮞ ATIVAR CRON${NC}"
        echo -e "${C}┃ ${G}08${W} ⮞ VINCULAR HWID            ${C}┃ ${R}00${W} ⮞ SAIR${NC}"
        echo -e "${C}┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛${NC}"
        read -p "➤ Opção: " op
        case $op in
            1|01) criar_usuario ;; 2|02) listar_usuarios ;; 3|03) remover_usuario_direto ;;
            4|04) alterar_validade_direto ;; 5|05) usuarios_vencidos ;; 6|06) mostrar_usuarios_online ;;
            7|07) recuperar_senha ;; 8|08) atualizar_hwid ;; 9|09) novo_chamado ;;
            10) gerenciar_chamados ;; 11) configurar_smtp ;; 12) install_deps ;;
            13) install_squid ;; 14) install_sslh ;; 15) configurar_cron_monitor ;;
            0|00) exit 0 ;;
        esac
    done
}

# --- INICIALIZAÇÃO ---
[ "$1" == "--cron-monitor" ] && exit 0
menu
