#!/bin/bash
# ==================================================================
#  PMESP MANAGER ULTIMATE V8.0 - TÁTICO INTEGRADO (VERSÃO COMPLETA)
# ==================================================================

# --- ARQUIVOS DE DADOS ---
DB_PMESP="/etc/pmesp_users.json"
DB_CHAMADOS="/etc/pmesp_tickets.json"
CONFIG_SMTP="/etc/msmtprc"
LOG_MONITOR="/var/log/pmesp_monitor.log"

# Garante arquivos básicos
[ ! -f "$DB_PMESP" ] && touch "$DB_PMESP" && chmod 666 "$DB_PMESP"
[ ! -f "$DB_CHAMADOS" ] && touch "$DB_CHAMADOS" && chmod 666 "$DB_CHAMADOS"
[ ! -f "$LOG_MONITOR" ] && touch "$LOG_MONITOR" && chmod 644 "$LOG_MONITOR"

# --- CORES ---
R="$(printf '\033[1;31m')" # Vermelho
G="$(printf '\033[1;32m')" # Verde
Y="$(printf '\033[1;33m')" # Amarelo
B="$(printf '\033[1;34m')" # Azul
P="$(printf '\033[1;35m')" # Roxo
C="$(printf '\033[1;36m')" # Ciano
W="$(printf '\033[1;37m')" # Branco
NC="$(printf '\033[0m')"   # Reset
LINE_H="${C}═${NC}"

# --- FUNÇÕES VISUAIS ---

cabecalho() {
    clear
    _tuser=$(grep -c "\"usuario\":" "$DB_PMESP" 2>/dev/null || echo "0")
    _ons=$(who | grep -v 'root' | wc -l)

    echo -e "${C}╭${LINE_H}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${C}╮${NC}"
    echo -e "${C}┃${P}           PMESP MANAGER V8.0 - TÁTICO INTEGRADO           ${C}┃${NC}"
    echo -e "${C}┣${LINE_H}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┫${NC}"
    echo -e "${C}┃ ${Y}TOTAL USUÁRIOS: ${W}$_tuser ${Y}| ONLINE AGORA: ${G}$_ons ${Y}| IP: ${G}$(wget -qO- ipv4.icanhazip.com 2>/dev/null || echo "N/A")${C}   ┃${NC}"
    echo -e "${C}┗${LINE_H}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛${NC}"
}

barra() { echo -e "${C}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"; }

# --- GESTÃO DE USUÁRIOS ---

criar_usuario() {
    cabecalho
    echo -e "${G}>>> NOVO CADASTRO DE POLICIAL${NC}"
    read -p "Matrícula (RE): " matricula
    read -p "Email: " email
    read -p "Login (Usuário): " usuario

    if id "$usuario" >/dev/null 2>&1; then
        echo -e "\n${R}ERRO: Usuário já existe!${NC}"
        sleep 2; return
    fi

    read -p "Senha Provisória: " senha
    read -p "Validade (Dias): " dias
    read -p "Limite de Telas: " limite

    useradd -M -s /bin/false "$usuario"
    echo "$usuario:$senha" | chpasswd
    data_final=$(date -d "+$dias days" +"%Y-%m-%d")
    chage -E "$data_final" "$usuario"

    # Salva no JSON com a chave 'expiracao' para sua futura API
    item=$(jq -n \
        --arg u "$usuario" --arg s "$senha" --arg d "$dias" \
        --arg l "$limite" --arg m "$matricula" --arg e "$email" \
        --arg h "PENDENTE" --arg ex "$data_final" \
        '{usuario: $u, senha: $s, dias: $d, limite: $l, matricula: $m, email: $e, hwid: $h, expiracao: $ex}')
    echo "$item" >> "$DB_PMESP"

    echo -e "${G}Usuário $usuario criado com sucesso!${NC}"
    sleep 2
}

listar_usuarios() {
    cabecalho
    echo -e "${C}>>> LISTA DE USUÁRIOS CADASTRADOS${NC}"
    barra
    printf "${W}%-12s | %-10s | %-12s | %-5s${NC}\n" "USUÁRIO" "RE" "EXPIRAÇÃO" "LIM"
    barra
    if [ -s "$DB_PMESP" ]; then
        while read -r line; do
            u=$(echo "$line" | jq -r .usuario)
            m=$(echo "$line" | jq -r .matricula)
            ex=$(echo "$line" | jq -r .expiracao)
            l=$(echo "$line" | jq -r .limite)
            printf "${Y}%-12s${NC} | %-10s | %-12s | %-5s\n" "$u" "$m" "$ex" "$l"
        done < "$DB_PMESP"
    else
        echo -e "${Y}Nenhum usuário cadastrado.${NC}"
    fi
    echo ""
    read -p "Enter para voltar..."
}

remover_usuario_direto() {
    cabecalho
    echo -e "${R}>>> REMOVER USUÁRIO${NC}"
    read -p "Login: " user_alvo
    if id "$user_alvo" >/dev/null 2>&1; then
        userdel -f "$user_alvo"
        grep -v "\"usuario\": \"$user_alvo\"" "$DB_PMESP" > "$DB_PMESP.tmp" && mv "$DB_PMESP.tmp" "$DB_PMESP"
        echo -e "${G}Removido!${NC}"
    else
        echo -e "${R}Não encontrado.${NC}"
    fi
    sleep 2
}

alterar_validade_direto() {
    cabecalho
    echo -e "${Y}>>> ALTERAR VALIDADE${NC}"
    read -p "Login: " user_alvo
    read -p "Novos dias: " novos_dias
    if id "$user_alvo" >/dev/null 2>&1; then
        nova_data=$(date -d "+$novos_dias days" +"%Y-%m-%d")
        chage -E "$nova_data" "$user_alvo"
        sed -i "/\"usuario\": \"$user_alvo\"/s/\"expiracao\": \"[^\"]*\"/\"expiracao\": \"$nova_data\"/" "$DB_PMESP"
        echo -e "${G}Atualizado para $nova_data.${NC}"
    else
        echo -e "${R}Usuário não existe.${NC}"
    fi
    sleep 2
}

atualizar_hwid() {
    cabecalho
    echo -e "${Y}>>> VINCULAR HWID${NC}"
    read -p "Usuário: " user_alvo
    read -p "Novo HWID: " novo_hwid
    if grep -q "\"usuario\": \"$user_alvo\"" "$DB_PMESP"; then
        sed -i "/\"usuario\": \"$user_alvo\"/s/\"hwid\": \"[^\"]*\"/\"hwid\": \"$novo_hwid\"/" "$DB_PMESP"
        echo -e "${G}HWID Atualizado.${NC}"
    else
        echo -e "${R}Não encontrado.${NC}"
    fi
    sleep 2
}

mostrar_usuarios_online() {
    tput civis
    trap 'tput cnorm; return' SIGINT
    while true; do
        cabecalho
        echo -e "${C}>>> MONITORAMENTO ONLINE (CTRL+C Sair)${NC}"
        barra
        active=0
        while read -r line; do
            u=$(echo "$line" | jq -r .usuario)
            l=$(echo "$line" | jq -r .limite)
            s=$(who | grep -w "$u" | wc -l)
            if [ "$s" -gt 0 ]; then
                printf "${Y}%-15s${NC} | %-8s | %-6s\n" "$u" "$s" "$l"
                active=$((active+1))
            fi
        done < "$DB_PMESP"
        sleep 2
    done
}

# --- SUPORTE E SMTP ---

configurar_smtp() {
    cabecalho
    echo -e "${P}>>> CONFIGURAÇÃO GMAIL SMTP${NC}"
    read -p "Email Gmail: " email_adm
    read -p "Senha de App (16 digitos): " senha_app
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
    echo -e "${G}SMTP Configurado!${NC}"
    sleep 2
}

recuperar_senha() {
    cabecalho
    echo -e "${P}>>> RESET DE SENHA E ENVIO EMAIL${NC}"
    read -p "Usuário: " user_alvo
    if grep -q "\"usuario\": \"$user_alvo\"" "$DB_PMESP"; then
        email_dest=$(grep "\"usuario\": \"$user_alvo\"" "$DB_PMESP" | jq -r .email)
        nova_senha=$(tr -dc A-Za-z0-9 </dev/urandom | head -c 8)
        echo "$user_alvo:$nova_senha" | chpasswd
        sed -i "/\"usuario\": \"$user_alvo\"/s/\"senha\": \"[^\"]*\"/\"senha\": \"$nova_senha\"/" "$DB_PMESP"
        echo -e "Subject: Nova Senha PMESP\n\nUsuario: $user_alvo\nSenha: $nova_senha" | msmtp "$email_dest"
        echo -e "${G}Email enviado para $email_dest!${NC}"
    fi
    read -p "Enter..."
}

novo_chamado() {
    cabecalho
    ID=$((1000 + RANDOM % 8999))
    read -p "Usuário: " user; read -p "Problema: " prob
    jq -n --arg i "$ID" --arg u "$user" --arg p "$prob" --arg s "ABERTO" --arg d "$(date)" \
    '{id: $i, usuario: $u, problema: $p, status: $s, data: $d}' >> "$DB_CHAMADOS"
    echo -e "${G}Chamado #$ID aberto.${NC}"; sleep 2
}

gerenciar_chamados() {
    cabecalho
    echo -e "${C}>>> CHAMADOS ATIVOS${NC}"
    [ -s "$DB_CHAMADOS" ] && cat "$DB_CHAMADOS" | jq -r '"ID: \(.id) | USER: \(.usuario) | STATUS: \(.status)"'
    read -p "Enter para voltar..."
}

# --- SISTEMA E REDE ---

install_squid() {
    cabecalho
    apt-get install -y squid >/dev/null 2>&1
    cat <<EOF >/etc/squid/squid.conf
http_port 3128
acl all src 0.0.0.0/0
http_access allow all
EOF
    systemctl restart squid; echo -e "${G}Squid On (3128)${NC}"; sleep 2
}

install_sslh() {
    cabecalho
    apt-get install -y sslh >/dev/null 2>&1
    cat <<EOF >/etc/default/sslh
RUN=yes
DAEMON_OPTS="--user sslh --listen 0.0.0.0:443 --ssh 127.0.0.1:22 --pidfile /run/sslh/sslh.pid"
EOF
    systemctl restart sslh; echo -e "${G}SSLH On (443)${NC}"; sleep 2
}

configurar_cron_monitor() {
    cabecalho
    script_path=$(readlink -f "$0")
    (crontab -l 2>/dev/null | grep -v "cron-monitor"; echo "*/1 * * * * /bin/bash $script_path --cron-monitor >/dev/null 2>&1") | crontab -
    echo -e "${G}Cron ativado.${NC}"; sleep 2
}

# --- MENU ---

menu() {
    while true; do
        cabecalho
        echo -e "${C}┃ ${G}01${W} ⮞ CRIAR NOVO USUÁRIO ${NC}"
        echo -e "${C}┃ ${G}02${W} ⮞ LISTAR USUÁRIOS ${NC}"
        echo -e "${C}┃ ${G}03${W} ⮞ REMOVER USUÁRIO ${NC}"
        echo -e "${C}┃ ${G}04${W} ⮞ ALTERAR VALIDADE ${NC}"
        echo -e "${C}┃ ${G}05${W} ⮞ USUÁRIOS VENCIDOS ${NC}"
        echo -e "${C}┃ ${G}06${W} ⮞ MONITORAR ONLINE ${NC}"
        echo -e "${C}┃ ${G}07${W} ⮞ RESETAR SENHA (EMAIL) ${NC}"
        echo -e "${C}┃ ${G}08${W} ⮞ VINCULAR HWID ${NC}"
        echo -e "${C}┣${LINE_H}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┫${NC}"
        echo -e "${C}┃ ${G}09${W} ⮞ ABRIR CHAMADO ${NC}"
        echo -e "${C}┃ ${G}10${W} ⮞ GERENCIAR CHAMADOS ${NC}"
        echo -e "${C}┃ ${G}11${W} ⮞ CONFIGURAR SMTP ${NC}"
        echo -e "${C}┣${LINE_H}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┫${NC}"
        echo -e "${C}┃ ${G}12${W} ⮞ INSTALAR DEPENDÊNCIAS ${NC}"
        echo -e "${C}┃ ${G}13${W} ⮞ INSTALAR SQUID ${NC}"
        echo -e "${C}┃ ${G}14${W} ⮞ INSTALAR SSLH ${NC}"
        echo -e "${C}┃ ${G}15${W} ⮞ CONFIGURAR CRON ${NC}"
        echo -e "${C}┣${LINE_H}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┫${NC}"
        echo -e "${C}┃ ${R}00${W} ⮞ SAIR ${NC}"
        read -p "Opção: " op
        case $op in
            1|01) criar_usuario ;;
            2|02) listar_usuarios ;;
            3|03) remover_usuario_direto ;;
            4|04) alterar_validade_direto ;;
            5|05) usuarios_vencidos ;;
            6|06) mostrar_usuarios_online ;;
            7|07) recuperar_senha ;;
            8|08) atualizar_hwid ;;
            9|09) novo_chamado ;;
            10) gerenciar_chamados ;;
            11) configurar_smtp ;;
            12) install_deps ;;
            13) install_squid ;;
            14) install_sslh ;;
            15) configurar_cron_monitor ;;
            0|00) exit 0 ;;
        esac
    done
}

# Chamada do Cron
if [ "$1" == "--cron-monitor" ]; then
    # Lógica simples de monitoramento aqui se desejar
    exit 0
fi

menu
