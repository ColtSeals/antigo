#!/bin/bash
# ==================================================================
#  PMESP MANAGER ULTIMATE V8.0 - TÁTICO INTEGRADO (VERSÃO FINAL)
# ==================================================================

# --- CONFIGURAÇÃO DE ARQUIVOS ---
DB_PMESP="/etc/pmesp_users.json"
DB_CHAMADOS="/etc/pmesp_tickets.json"
CONFIG_SMTP="/etc/msmtprc"
LOG_MONITOR="/var/log/pmesp_monitor.log"

# Garante que os arquivos existam e tenham permissão
[ ! -f "$DB_PMESP" ] && touch "$DB_PMESP" && chmod 666 "$DB_PMESP"
[ ! -f "$DB_CHAMADOS" ] && touch "$DB_CHAMADOS" && chmod 666 "$DB_CHAMADOS"
[ ! -f "$LOG_MONITOR" ] && touch "$LOG_MONITOR" && chmod 644 "$LOG_MONITOR"

# --- DEFINIÇÃO DE CORES ---
R="\033[1;31m"; G="\033[1;32m"; Y="\033[1;33m"; B="\033[1;34m"
P="\033[1;35m"; C="\033[1;36m"; W="\033[1;37m"; NC="\033[0m"
LINE_H="${C}═${NC}"

# --- FUNÇÕES VISUAIS ---

cabecalho() {
    clear
    # Contador corrigido para não quebrar a linha
    _tuser=$(grep -c "\"usuario\":" "$DB_PMESP" 2>/dev/null || echo "0")
    _ons=$(who | grep -v 'root' | wc -l)
    _ip=$(wget -qO- ipv4.icanhazip.com 2>/dev/null || echo "N/A")

    echo -e "${C}╭${LINE_H}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${C}╮${NC}"
    echo -e "${C}┃${P}           PMESP MANAGER V8.0 - TÁTICO INTEGRADO           ${C}┃${NC}"
    echo -e "${C}┣${LINE_H}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┫${NC}"
    echo -e "${C}┃ ${Y}TOTAL: ${W}$_tuser ${Y}| ONLINE: ${G}$_ons ${Y}| IP: ${G}$_ip${C}   ┃${NC}"
    echo -e "${C}┗${LINE_H}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛${NC}"
}

barra() { echo -e "${C}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"; }

# --- GESTÃO DE USUÁRIOS ---

criar_usuario() {
    cabecalho
    echo -e "${G}>>> NOVO CADASTRO DE POLICIAL${NC}"
    read -p "Matrícula (RE): " matricula
    read -p "Email do Policial: " email
    read -p "Login (Usuário): " usuario
    [ -z "$usuario" ] && return
    
    if id "$usuario" >/dev/null 2>&1; then 
        echo -e "\n${R}ERRO: Usuário já existe!${NC}"
        sleep 2; return
    fi

    read -p "Senha Provisória: " senha
    read -p "Validade (Dias): " dias
    read -p "Limite de Telas: " limite

    # 1. Sistema Linux
    useradd -M -s /bin/false "$usuario"
    echo "$usuario:$senha" | chpasswd
    data_exp=$(date -d "+$dias days" +"%Y-%m-%d")
    chage -E "$data_exp" "$usuario"

    # 2. Banco de Dados JSON (Garante JQ instalado)
    if ! command -v jq &> /dev/null; then apt install jq -y >/dev/null; fi
    
    item=$(jq -n --arg u "$usuario" --arg s "$senha" --arg d "$dias" --arg l "$limite" \
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
    printf "${W}%-12s | %-10s | %-11s | %-5s | %-10s${NC}\n" "USUÁRIO" "RE" "EXPIRA" "LIM" "HWID"
    barra
    if [ -s "$DB_PMESP" ]; then
        while read -r line; do
            u=$(echo "$line" | jq -r .usuario); m=$(echo "$line" | jq -r .matricula)
            ex=$(echo "$line" | jq -r .expiracao); l=$(echo "$line" | jq -r .limite)
            h=$(echo "$line" | jq -r .hwid)
            printf "${Y}%-12s${NC} | %-10s | %-11s | %-5s | %-10s\n" "$u" "$m" "$ex" "$l" "${h:0:10}"
        done < "$DB_PMESP"
    else
        echo -e "${R}Nenhum usuário no banco de dados.${NC}"
    fi
    echo ""
    read -p "Pressione Enter para voltar..."
}

remover_usuario_direto() {
    cabecalho
    echo -e "${R}>>> REMOVER USUÁRIO${NC}"
    read -p "Digite o login: " user_alvo
    if id "$user_alvo" >/dev/null 2>&1; then
        userdel -f "$user_alvo"
        grep -v "\"usuario\": \"$user_alvo\"" "$DB_PMESP" > "$DB_PMESP.tmp" && mv "$DB_PMESP.tmp" "$DB_PMESP"
        echo -e "${G}Removido com sucesso!${NC}"
    else
        echo -e "${R}Usuário não encontrado.${NC}"
    fi
    sleep 2
}

alterar_validade_direto() {
    cabecalho
    echo -e "${Y}>>> ALTERAR VALIDADE${NC}"
    read -p "Login: " user_alvo
    read -p "Novos dias a contar de hoje: " novos_dias
    if id "$user_alvo" >/dev/null 2>&1; then
        nova_data=$(date -d "+$novos_dias days" +"%Y-%m-%d")
        chage -E "$nova_data" "$user_alvo"
        # Atualiza JSON
        tmp=$(mktemp)
        while read -r line; do
            if echo "$line" | grep -q "\"usuario\": \"$user_alvo\""; then
                echo "$line" | jq --arg d "$novos_dias" --arg ex "$nova_data" '.dias=$d | .expiracao=$ex' >> "$tmp"
            else
                echo "$line" >> "$tmp"
            fi
        done < "$DB_PMESP"
        mv "$tmp" "$DB_PMESP"
        echo -e "${G}Validade atualizada para $nova_data!${NC}"
    else
        echo -e "${R}Usuário não existe.${NC}"
    fi
    sleep 2
}

atualizar_hwid() {
    cabecalho
    echo -e "${Y}>>> VINCULAR/RESETAR HWID${NC}"
    read -p "Usuário: " user_alvo
    read -p "Novo HWID (ou PENDENTE): " novo_hwid
    if grep -q "\"usuario\": \"$user_alvo\"" "$DB_PMESP"; then
        tmp=$(mktemp)
        while read -r line; do
            if echo "$line" | grep -q "\"usuario\": \"$user_alvo\""; then
                echo "$line" | jq --arg h "$novo_hwid" '.hwid=$h' >> "$tmp"
            else
                echo "$line" >> "$tmp"
            fi
        done < "$DB_PMESP"
        mv "$tmp" "$DB_PMESP"
        echo -e "${G}HWID Atualizado!${NC}"
    fi
    sleep 2
}

# --- MONITORAMENTO E SUPORTE ---

mostrar_usuarios_online() {
    tput civis
    trap 'tput cnorm; return' SIGINT
    while true; do
        cabecalho
        echo -e "${C}>>> MONITORAMENTO REAL-TIME (CTRL+C Sair)${NC}"
        barra
        printf "${W}%-15s | %-10s | %-6s${NC}\n" "USUÁRIO" "SESSÕES" "LIMITE"
        barra
        active=0
        while read -r line; do
            u=$(echo "$line" | jq -r .usuario); l=$(echo "$line" | jq -r .limite)
            s=$(who | grep -w "$u" | wc -l)
            if [ "$s" -gt 0 ]; then
                printf "${Y}%-15s${NC} | %-10s | %-6s\n" "$u" "$s" "$l"
                active=$((active+1))
            fi
        done < "$DB_PMESP"
        [ "$active" -eq 0 ] && echo -e "${Y}Ninguém online agora.${NC}"
        sleep 2
    done
}

configurar_smtp() {
    cabecalho
    echo -e "${P}>>> CONFIGURAÇÃO SMTP GMAIL${NC}"
    read -p "E-mail: " email_adm
    read -p "Senha de App (Google): " senha_app
    cat <<EOF > "$CONFIG_SMTP"
defaults
auth on
tls on
tls_trust_file /etc/ssl/certs/ca-certificates.crt
account gmail
host smtp.gmail.com
port 587
from $email_adm
user $email_adm
password $senha_app
account default : gmail
EOF
    chmod 600 "$CONFIG_SMTP"
    echo -e "${G}SMTP Configurado!${NC}"; sleep 2
}

recuperar_senha() {
    cabecalho
    read -p "Usuário para reset: " user_alvo
    if grep -q "\"usuario\": \"$user_alvo\"" "$DB_PMESP"; then
        email_dest=$(grep "\"usuario\": \"$user_alvo\"" "$DB_PMESP" | jq -r .email)
        nova_senha=$(tr -dc A-Za-z0-9 </dev/urandom | head -c 8)
        echo "$user_alvo:$nova_senha" | chpasswd
        # Atualiza JSON
        sed -i "/\"usuario\": \"$user_alvo\"/s/\"senha\": \"[^\"]*\"/\"senha\": \"$nova_senha\"/" "$DB_PMESP"
        echo -e "Subject: Nova Senha PMESP\n\nUsuario: $user_alvo\nNova Senha: $nova_senha" | msmtp "$email_dest"
        echo -e "${G}Senha enviada para $email_dest!${NC}"
    fi
    read -p "Enter..."
}

# --- REDE E SISTEMA ---

install_squid() {
    cabecalho
    echo -e "${B}Instalando Squid Proxy...${NC}"
    apt install squid -y >/dev/null
    cat <<EOF > /etc/squid/squid.conf
http_port 3128
acl all src 0.0.0.0/0
http_access allow all
EOF
    systemctl restart squid; echo -e "${G}Squid na porta 3128!${NC}"; sleep 2
}

install_sslh() {
    cabecalho
    apt install sslh -y >/dev/null
    cat <<EOF > /etc/default/sslh
RUN=yes
DAEMON_OPTS="--user sslh --listen 0.0.0.0:443 --ssh 127.0.0.1:22 --pidfile /run/sslh/sslh.pid"
EOF
    systemctl restart sslh; echo -e "${G}SSLH na porta 443!${NC}"; sleep 2
}

configurar_cron_monitor() {
    cabecalho
    script_path=$(readlink -f "$0")
    (crontab -l 2>/dev/null | grep -v "cron-monitor"; echo "*/1 * * * * /bin/bash $script_path --cron-monitor >/dev/null 2>&1") | crontab -
    echo -e "${G}Monitor de Limite (Cron) Ativado!${NC}"; sleep 2
}

monitorar_acessos_cron() {
    # Lógica silenciosa para o Cron
    while read -r line; do
        u=$(echo "$line" | jq -r .usuario); lim=$(echo "$line" | jq -r .limite)
        s=$(who | grep -w "$u" | wc -l)
        if [ "$lim" -gt 0 ] && [ "$s" -gt "$lim" ]; then
            pkill -u "$u"
            echo "$(date) - Usuário $u derrubado (Limite $lim excedido)" >> "$LOG_MONITOR"
        fi
    done < "$DB_PMESP"
}

# --- MENU PRINCIPAL ---

menu() {
    while true; do
        cabecalho
        echo -e "${C}┃ ${G}01${W} ⮞ CRIAR NOVO USUÁRIO          ${C}┃ ${G}09${W} ⮞ ABRIR CHAMADO${NC}"
        echo -e "${C}┃ ${G}02${W} ⮞ LISTAR USUÁRIOS             ${C}┃ ${G}10${W} ⮞ GERENCIAR CHAMADOS${NC}"
        echo -e "${C}┃ ${G}03${W} ⮞ REMOVER USUÁRIO             ${C}┃ ${G}11${W} ⮞ CONFIGURAR SMTP${NC}"
        echo -e "${C}┃ ${G}04${W} ⮞ ALTERAR VALIDADE            ${C}┃ ${G}12${W} ⮞ INSTALAR DEPENDENCIAS${NC}"
        echo -e "${C}┃ ${G}05${W} ⮞ USUÁRIOS VENCIDOS           ${C}┃ ${G}13${W} ⮞ INSTALAR SQUID${NC}"
        echo -e "${C}┃ ${G}06${W} ⮞ MONITORAR ONLINE            ${C}┃ ${G}14${W} ⮞ INSTALAR SSLH${NC}"
        echo -e "${C}┃ ${G}07${W} ⮞ RESETAR SENHA (EMAIL)       ${C}┃ ${G}15${W} ⮞ ATIVAR MONITOR CRON${NC}"
        echo -e "${C}┃ ${G}08${W} ⮞ VINCULAR/RESETAR HWID       ${C}┃ ${R}00${W} ⮞ SAIR${NC}"
        echo -e "${C}┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛${NC}"
        read -p "➤ Opção: " op
        case $op in
            1|01) criar_usuario ;;
            2|02) listar_usuarios ;;
            3|03) remover_usuario_direto ;;
            4|04) alterar_validade_direto ;;
            6|06) mostrar_usuarios_online ;;
            7|07) recuperar_senha ;;
            8|08) atualizar_hwid ;;
            11) configurar_smtp ;;
            12) apt update && apt install jq -y ;;
            13) install_squid ;;
            14) install_sslh ;;
            15) configurar_cron_monitor ;;
            0|00) clear; exit 0 ;;
        esac
    done
}

# --- INICIALIZAÇÃO ---
if [ "$1" == "--cron-monitor" ]; then
    monitorar_acessos_cron
    exit 0
fi

menu
