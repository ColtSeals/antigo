#!/bin/bash
# ==================================================================
#  PMESP MANAGER ULTIMATE V8.0 - TÁTICO INTEGRADO (Menu Vertical Final)
# ==================================================================

# --- ARQUIVOS DE DADOS (Mantidos do Original) ---
DB_PMESP="/etc/pmesp_users.json"
DB_CHAMADOS="/etc/pmesp_tickets.json"
CONFIG_SMTP="/etc/msmtprc"
LOG_MONITOR="/var/log/pmesp_monitor.log"

# Garante arquivos básicos (Mantido do Original)
if [ ! -f "$DB_PMESP" ]; then
    touch "$DB_PMESP"
    chmod 666 "$DB_PMESP"
    echo "" > "$DB_PMESP"
fi

if [ ! -f "$DB_CHAMADOS" ]; then
    touch "$DB_CHAMADOS"
    chmod 666 "$DB_CHAMADOS"
fi

if [ ! -f "$LOG_MONITOR" ]; then
    touch "$LOG_MONITOR"
    chmod 644 "$LOG_MONITOR"
fi

# --- CORES (Adaptadas para Novo Layout) ---
R="$(printf '\033[1;31m')" # Vermelho (ERRO/SAIR)
G="$(printf '\033[1;32m')" # Verde (SUCESSO)
Y="$(printf '\033[1;33m')" # Amarelo (ALERTA)
B="$(printf '\033[1;34m')" # Azul
P="$(printf '\033[1;35m')" # Roxo/Magenta
C="$(printf '\033[1;36m')" # Ciano (DIVISOR)
W="$(printf '\033[1;37m')" # Branco (OPÇÕES)
NC="$(printf '\033[0m')"  # Reset
LINE_H="${C}═${NC}"

# --- FUNÇÕES VISUAIS ---

cabecalho() {
    clear
    # Informações de Status Dinâmico
    _tuser=$(jq '.usuario' "$DB_PMESP" 2>/dev/null | wc -l)
    _ons=$(who | grep -v 'root' | wc -l)

    echo -e "${C}╭${LINE_H}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${C}╮${NC}"
    echo -e "${C}┃${P}           PMESP MANAGER V8.0 - TÁTICO INTEGRADO           ${C}┃${NC}"
    echo -e "${C}┣${LINE_H}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┫${NC}"
    echo -e "${C}┃ ${Y}TOTAL USUÁRIOS: ${W}$_tuser ${Y}| ONLINE AGORA: ${G}$_ons ${Y}| IP: ${G}$(wget -qO- ipv4.icanhazip.com 2>/dev/null || echo "N/A")${C}   ┃${NC}"
    echo -e "${C}┗${LINE_H}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛${NC}"
}

barra() { echo -e "${C}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"; }

# --------------------------------------------------------------------------
# --- FUNÇÕES DE BACKEND (Incluindo as Novas Ações Diretas) ---
# --------------------------------------------------------------------------

# --- INSTALAÇÃO DE DEPENDÊNCIAS BÁSICAS ---
install_deps() {
    cabecalho
    echo -e "${Y}Instalando Dependências Básicas...${NC}"
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -y >/dev/null 2>&1
    apt-get install -y bc screen nano net-tools lsof cron zip unzip jq msmtp msmtp-mta ca-certificates >/dev/null 2>&1
    echo -e "${G}Sistema Pronto! Pacotes básicos instalados.${NC}"
    sleep 2
}

# --- CONFIGURAÇÃO DO GMAIL (SMTP) ---
configurar_smtp() {
    cabecalho
    echo -e "${P}>>> CONFIGURAÇÃO DE SERVIDOR DE E-MAIL (GMAIL)${NC}"
    echo "Necessário ter a 'Senha de App' gerada no Google."
    echo ""

    read -p "Seu E-mail Gmail (Ex: pmesp@gmail.com): " email_adm
    read -p "Sua Senha de App (16 letras): " senha_app

    echo -e "\n${Y}Configurando o cliente SMTP...${NC}"

    cat <<EOF > "$CONFIG_SMTP"
defaults
auth           on
tls            on
tls_trust_file /etc/ssl/certs/ca-certificates.crt
logfile        /var/log/msmtp.log

account        gmail
host           smtp.gmail.com
port           587
from           $email_adm
user           $email_adm
password       $senha_app

account default : gmail
EOF

    chmod 600 "$CONFIG_SMTP"

    echo -e "${G}Configuração salva em $CONFIG_SMTP!${NC}"
    echo -e "Enviando e-mail de teste para você mesmo..."

    echo -e "Subject: Teste PMESP Manager\n\nO sistema de e-mail da VPS esta operante." | msmtp "$email_adm"

    if [ $? -eq 0 ]; then
        echo -e "${G}E-mail de teste enviado! Verifique sua caixa de entrada.${NC}"
    else
        echo -e "${R}Erro ao enviar. Verifique se a senha de app está correta.${NC}"
    fi
    read -p "Enter para voltar..."
}

# --- GESTÃO DE USUÁRIOS (Criar) ---
criar_usuario() {
    cabecalho
    echo -e "${G}>>> NOVO CADASTRO DE USUÁRIO${NC}"
    read -p "Matrícula (RE): " matricula
    read -p "Email do Policial: " email
    read -p "Login (Usuário): " usuario

    if id "$usuario" >/dev/null 2>&1; then
        echo -e "\n${R}ERRO: Usuário já existe!${NC}"
        sleep 2
        return
    fi

    read -p "Senha Provisória: " senha
    read -p "Validade (Dias): " dias
    read -p "Limite de Telas (Sessões): " limite

    # Usuário Linux sem shell
    useradd -M -s /bin/false "$usuario"
    echo "$usuario:$senha" | chpasswd

    # Validade
    data_final=$(date -d "+$dias days" +"%Y-%m-%d")
    chage -E "$data_final" "$usuario"

    # Registra no "JSON" (1 objeto por linha)
    jq -n \
        --arg u "$usuario" \
        --arg s "$senha" \
        --arg d "$dias" \
        --arg l "$limite" \
        --arg m "$matricula" \
        --arg e "$email" \
        --arg h "PENDENTE" \
        '{usuario: $u, senha: $s, dias: $d, limite: $l, matricula: $m, email: $e, hwid: $h}' \
        >> "$DB_PMESP"

    echo -e "${G}Usuário Criado!${NC}"
    read -p "Enter..."
}

# --- HWID ---
atualizar_hwid() {
    cabecalho
    echo -e "${Y}>>> VINCULAR HWID${NC}"
    read -p "Usuário alvo: " user_alvo
    read -p "Novo HWID: " novo_hwid

    if ! grep -q "\"usuario\": \"$user_alvo\"" "$DB_PMESP"; then
        echo -e "${R}Usuário não encontrado!${NC}"
        sleep 2
        return
    fi

    linha=$(grep "\"usuario\": \"$user_alvo\"" "$DB_PMESP")
    s=$(echo "$linha" | jq -r .senha)
    d=$(echo "$linha" | jq -r .dias)
    l=$(echo "$linha" | jq -r .limite)
    m=$(echo "$linha" | jq -r .matricula)
    e=$(echo "$linha" | jq -r .email)

    grep -v "\"usuario\": \"$user_alvo\"" "$DB_PMESP" > "${DB_PMESP}.tmp" && mv "${DB_PMESP}.tmp" "$DB_PMESP"

    jq -n \
        --arg u "$user_alvo" \
        --arg s "$s" \
        --arg d "$d" \
        --arg l "$l" \
        --arg m "$m" \
        --arg e "$e" \
        --arg h "$novo_hwid" \
        '{usuario: $u, senha: $s, dias: $d, limite: $l, matricula: $m, email: $e, hwid: $h}' \
        >> "$DB_PMESP"

    echo -e "${G}HWID Atualizado.${NC}"
    sleep 2
}

# --- LISTAR USUÁRIOS (Opção 02) ---
listar_usuarios() {
    cabecalho
    echo -e "${C}>>> LISTA DE USUÁRIOS CADASTRADOS${NC}"
    barra

    echo -e "${W}%-15s | %-10s | %-5s | %-5s | %s${NC}" "USUÁRIO" "MATRÍCULA" "DIAS" "LIM" "HWID"
    barra

    if [ -s "$DB_PMESP" ]; then
        while IFS= read -r line; do
            [ -z "$line" ] && continue
            usuario=$(echo "$line" | jq -r '.usuario // empty' 2>/dev/null)
            [ -z "$usuario" ] && continue
            [ "$usuario" = "null" ] && continue

            matricula=$(echo "$line" | jq -r '.matricula // "-"')
            dias=$(echo "$line" | jq -r '.dias // "-"')
            limite=$(echo "$line" | jq -r '.limite // "-"')
            hwid=$(echo "$line" | jq -r '.hwid // "-"')

            # Truncar HWID para melhor visualização
            hwid_short="${hwid:0:15}..."

            printf "${Y}%-15s${NC} | %-10s | %-5s | %-5s | %s\n" \
                "$usuario" "$matricula" "$dias" "$limite" "$hwid_short"
        done < <(jq -c '.' "$DB_PMESP" 2>/dev/null)
    else
        echo -e "${Y}Nenhum usuário cadastrado.${NC}"
    fi

    echo ""
    read -p "Enter para voltar..."
}

# --- REMOVER USUÁRIO (NOVA FUNÇÃO DIRETA - Opção 03) ---
remover_usuario_direto() {
    cabecalho
    echo -e "${R}>>> REMOVER USUÁRIO (DELETAR)${NC}"
    read -p "Digite o LOGIN do usuário que deseja remover: " user_alvo

    if ! id "$user_alvo" >/dev/null 2>&1 || ! grep -q "\"usuario\": \"$user_alvo\"" "$DB_PMESP"; then
        echo -e "${R}ERRO: Usuário $user_alvo não existe no sistema ou no banco de dados.${NC}"
        sleep 2
        return
    fi

    read -p "Tem certeza que deseja remover $user_alvo? (s/N): " confirmacao
    if [[ "$confirmacao" =~ ^[Ss]$ ]]; then
        userdel -f "$user_alvo" >/dev/null 2>&1
        grep -v "\"usuario\": \"$user_alvo\"" "$DB_PMESP" > "${DB_PMESP}.tmp" && mv "${DB_PMESP}.tmp" "$DB_PMESP"
        echo -e "${G}Usuário $user_alvo removido com sucesso.${NC}"
    else
        echo -e "${Y}Operação cancelada.${NC}"
    fi
    sleep 2
}

# --- ALTERAR VALIDADE (NOVA FUNÇÃO DIRETA - Opção 04) ---
alterar_validade_direto() {
    cabecalho
    echo -e "${Y}>>> ALTERAR VALIDADE DE USUÁRIO (DIAS)${NC}"
    read -p "Digite o LOGIN do usuário: " user_alvo

    if ! grep -q "\"usuario\": \"$user_alvo\"" "$DB_PMESP"; then
        echo -e "${R}ERRO: Usuário $user_alvo não encontrado no banco de dados.${NC}"
        sleep 2
        return
    fi

    read -p "Nova validade em dias a partir de hoje: " novos_dias
    if ! [[ "$novos_dias" =~ ^[0-9]+$ ]]; then
        echo -e "${R}Valor inválido.${NC}"
        sleep 2
        return
    fi

    nova_data=$(date -d "+$novos_dias days" +"%Y-%m-%d")
    chage -E "$nova_data" "$user_alvo"

    # Atualizar o JSON com os novos dias
    linha=$(grep "\"usuario\": \"$user_alvo\"" "$DB_PMESP")
    s=$(echo "$linha" | jq -r .senha)
    l=$(echo "$linha" | jq -r .limite)
    m=$(echo "$linha" | jq -r .matricula)
    e=$(echo "$linha" | jq -r .email)
    h=$(echo "$linha" | jq -r .hwid)

    grep -v "\"usuario\": \"$user_alvo\"" "$DB_PMESP" > "${DB_PMESP}.tmp" && mv "${DB_PMESP}.tmp" "$DB_PMESP"

    jq -n \
        --arg u "$user_alvo" \
        --arg s "$s" \
        --arg d "$novos_dias" \
        --arg l "$l" \
        --arg m "$m" \
        --arg e "$e" \
        --arg h "$h" \
        '{usuario: $u, senha: $s, dias: $d, limite: $l, matricula: $m, email: $e, hwid: $h}' \
        >> "$DB_PMESP"

    echo -e "${G}Validade de $user_alvo atualizada para $novos_dias dias (até $nova_data).${NC}"
    sleep 2
}

# --- USUÁRIOS VENCIDOS (Opção 05) ---
usuarios_vencidos() {
    cabecalho
    echo -e "${R}>>> USUÁRIOS EXPIRADOS OU PRÓXIMOS DA EXPIRAÇÃO (7 DIAS)${NC}"
    barra

    echo -e "${W}%-15s | %-12s | %s${NC}" "USUÁRIO" "DATA EXPIRAÇÃO" "STATUS"
    barra

    if [ -s "$DB_PMESP" ]; then
        today_seconds=$(date +%s)
        seven_days_seconds=$((today_seconds + 60*60*24*7))

        while IFS= read -r line; do
            [ -z "$line" ] && continue
            usuario=$(echo "$line" | jq -r '.usuario // empty' 2>/dev/null)
            [ -z "$usuario" ] && continue

            expire_date_raw=$(chage -l "$usuario" 2>/dev/null | grep 'Account expires' | awk -F ': ' '{print $2}')

            if [ "$expire_date_raw" = "never" ]; then
                continue
            fi

            expire_seconds=$(date -d "$expire_date_raw" +%s 2>/dev/null)

            if [ -z "$expire_seconds" ]; then
                continue
            fi

            if [ "$expire_seconds" -lt "$today_seconds" ]; then
                status="${R}EXPIRADO${NC}"
                printf "%-15s | %-12s | %s\n" "${R}$usuario${NC}" "$expire_date_raw" "$status"
            elif [ "$expire_seconds" -lt "$seven_days_seconds" ]; then
                status="${Y}PRÓXIMO${NC}"
                printf "%-15s | %-12s | %s\n" "${Y}$usuario${NC}" "$expire_date_raw" "$status"
            fi
        done < <(jq -c '.' "$DB_PMESP" 2>/dev/null)
    else
        echo -e "${Y}Nenhum usuário cadastrado.${NC}"
    fi

    echo ""
    read -p "Enter para voltar..."
}


# --- MONITORAMENTO ONLINE (NOVO LOOP CONTÍNUO E CORREÇÃO DE REPETIÇÃO - Opção 06) ---
mostrar_usuarios_online() {
    tput civis # Esconde o cursor

    # Adiciona armadilha para Ctrl+C para garantir que o cursor volte e o loop pare
    trap 'tput cnorm; clear; return' SIGINT

    clear
    echo -e "${R}Pressione CTRL + C para retornar ao menu principal.${NC}"
    sleep 1

    while true; do
        cabecalho
        echo -e "${C}>>> MONITORAMENTO ONLINE EM TEMPO REAL ${Y}(Atualiza a cada 2s)${NC}"
        barra
        printf "${W}%-15s | %-8s | %-6s${NC}\n" "Usuário" "Sessões" "Limite"
        barra

        local active_sessions=0

        # Leitura do banco de dados, filtrando por usuários únicos.
        if [ -s "$DB_PMESP" ]; then
            # Usamos `jq -s . | jq 'unique_by(.usuario)[]'` para garantir que cada usuário seja lido apenas uma vez.
            jq -c '.' "$DB_PMESP" 2>/dev/null | \
            jq -s '.' 2>/dev/null | \
            jq -c 'unique_by(.usuario)[]' 2>/dev/null | \
            while read -r line; do
                [ -z "$line" ] && continue
                user=$(echo "$line" | jq -r '.usuario // empty' 2>/dev/null)
                [ -z "$user" ] && continue
                [ "$user" = "null" ] && continue

                limite=$(echo "$line" | jq -r '.limite')
                [ -z "$limite" ] && limite=0

                # Verifica as sessões SSH ativas para o usuário
                sessoes=$(who | awk -v user="$user" '$1==user {c++} END {print c+0}')

                if [ "$sessoes" -gt 0 ]; then
                    active_sessions=$((active_sessions + 1))
                    # REMOÇÃO DO PISCA-PISCA: Apenas cor amarela (Y)
                    printf "${Y}%-15s${NC} | %-8s | %-6s\n" "$user" "$sessoes" "$limite"
                fi
            done
        fi

        if [ "$active_sessions" -eq 0 ]; then
            echo -e "${Y}Nenhum usuário online no momento.${NC}"
        fi

        sleep 2
        # Move o cursor para cima para reescrever a lista
        # O valor 6 é a contagem de linhas fixas após o cabecalho
        tput cuu $((active_sessions + 6))
        tput ed # Limpa o restante da tela
    done
}


# --- RECUPERAÇÃO DE SENHA (Opção 07) ---
recuperar_senha() {
    cabecalho
    echo -e "${P}>>> RESETAR SENHA E ENVIAR EMAIL${NC}"

    if [ ! -f "$CONFIG_SMTP" ]; then
        echo -e "${R}ERRO: Configure o SMTP primeiro!${NC}"
        sleep 3
        return
    fi

    read -p "Usuário para reset: " user_alvo

    if ! grep -q "\"usuario\": \"$user_alvo\"" "$DB_PMESP"; then
        echo -e "${R}Usuário não existe.${NC}"
        sleep 2
        return
    fi

    linha=$(grep "\"usuario\": \"$user_alvo\"" "$DB_PMESP")
    email_dest=$(echo "$linha" | jq -r .email)

    if [ -z "$email_dest" ] || [ "$email_dest" == "null" ]; then
        echo -e "${R}Usuário sem e-mail cadastrado.${NC}"
        sleep 2
        return
    fi

    nova_senha=$(tr -dc A-Za-z0-9 </dev/urandom | head -c 8)
    echo "$user_alvo:$nova_senha" | chpasswd

    grep -v "\"usuario\": \"$user_alvo\"" "$DB_PMESP" > "${DB_PMESP}.tmp" && mv "${DB_PMESP}.tmp" "$DB_PMESP"

    jq -n \
        --arg u "$user_alvo" \
        --arg s "$nova_senha" \
        --arg d "$(echo "$linha" | jq -r .dias)" \
        --arg l "$(echo "$linha" | jq -r .limite)" \
        --arg m "$(echo "$linha" | jq -r .matricula)" \
        --arg e "$email_dest" \
        --arg h "$(echo "$linha" | jq -r .hwid)" \
        '{usuario: $u, senha: $s, dias: $d, limite: $l, matricula: $m, email: $e, hwid: $h}' \
        >> "$DB_PMESP"

    echo -e "Enviando e-mail para ${Y}$email_dest${NC}..."

    (
        echo "To: $email_dest"
        echo "Subject: [PMESP] Nova Senha de Acesso"
        echo "MIME-Version: 1.0"
        echo "Content-Type: text/plain; charset=utf-8"
        echo ""
        echo "==== SISTEMA INTEGRADO PMESP ===="
        echo ""
        echo "Solicitação de reset de senha processada."
        echo ""
        echo "Usuário: $user_alvo"
        echo "Nova Senha: $nova_senha"
        echo ""
        echo "Favor alterar sua senha assim que possível."
        echo "================================="
    ) | msmtp "$email_dest"

    if [ $? -eq 0 ]; then
        echo -e "${G}SUCESSO! E-mail enviado.${NC}"
    else
        echo -e "${R}FALHA NO ENVIO. Senha gerada: $nova_senha${NC}"
    fi
    read -p "Enter..."
}

# --- SISTEMA DE CHAMADOS ---
novo_chamado() {
    cabecalho
    echo -e "${C}>>> NOVO CHAMADO${NC}"
    ID=$((1000 + RANDOM % 8999))
    DATA=$(date "+%d/%m/%Y %H:%M")
    read -p "Usuário: " user
    read -p "Problema: " prob

    jq -n \
        --arg i "$ID" \
        --arg u "$user" \
        --arg p "$prob" \
        --arg s "ABERTO" \
        --arg d "$DATA" \
        '{id: $i, usuario: $u, problema: $p, status: $s, data: $d}' \
        >> "$DB_CHAMADOS"

    echo -e "${G}Chamado #$ID criado.${NC}"
    sleep 2
}

gerenciar_chamados() {
    while true; do
        cabecalho
        echo -e "${C}>>> GERENCIAR CHAMADOS${NC}"
        printf "${B}%-6s | %-12s | %-10s | %-20s${NC}\n" "ID" "USER" "STATUS" "DESC"
        barra

        while read -r line; do
            [ -z "$line" ] && continue
            i=$(echo "$line" | jq -r .id)
            u=$(echo "$line" | jq -r .usuario)
            p=$(echo "$line" | jq -r .problema)
            s=$(echo "$line" | jq -r .status)

            if [ "$s" == "ABERTO" ]; then
                Col=$R
            else
                Col=$G
            fi

            printf "%-6s | %-12s | ${Col}%-10s${NC} | %-20s\n" "$i" "$u" "$s" "${p:0:20}..."
        done < "$DB_CHAMADOS"

        echo ""
        echo "[1] Fechar Chamado | [2] Deletar Chamado | [0] Voltar"
        read -p "Op: " opc

        case $opc in
            1)
                read -p "ID: " id
                tmp=$(mktemp)
                while read -r l; do
                    [ -z "$l" ] && continue
                    cid=$(echo "$l" | jq -r .id)
                    if [ "$cid" == "$id" ]; then
                        echo "$l" | jq '.status="ENCERRADO"' >> "$tmp"
                    else
                        echo "$l" >> "$tmp"
                    fi
                done < "$DB_CHAMADOS"
                mv "$tmp" "$DB_CHAMADOS"
                ;;
            2)
                read -p "ID: " id
                grep -v "\"id\": \"$id\"" "$DB_CHAMADOS" > t.json && mv t.json "$DB_CHAMADOS"
                ;;
            0)
                return
                ;;
        esac
    done
}


# --- INSTALAR SQUID (PROXY HTTP LIBERADO) ---
install_squid() {
    cabecalho
    echo -e "${C}>>> INSTALAÇÃO DO SQUID (PROXY HTTP)${NC}"
    echo "Instalando pacote squid..."
    apt-get update -y >/dev/null 2>&1
    apt-get install -y squid >/dev/null 2>&1

    if [ -f /etc/squid/squid.conf ]; then
        cp /etc/squid/squid.conf "/etc/squid/squid.conf.bak_$(date +%F_%H%M%S)"
    fi

    cat <<EOF >/etc/squid/squid.conf
# ============================================
#  SQUID - CONFIG BÁSICA PMESP MANAGER
#  Proxy liberado (ajuste ACL depois se quiser)
# ============================================
http_port 3128

acl all src 0.0.0.0/0
http_access allow all

cache_mem 64 MB
maximum_object_size_in_memory 512 KB
cache_dir ufs /var/spool/squid 100 16 256

access_log daemon:/var/log/squid/access.log squid
cache_log /var/log/squid/cache.log
EOF

    systemctl enable squid >/dev/null 2>&1
    systemctl restart squid

    echo ""
    echo -e "${G}SQUID instalado e rodando na porta 3128.${NC}"
    echo "No Windows, configure o navegador para usar o PROXY HTTP:"
    echo "  IP da VPS  : porta 3128"
    echo ""
    echo -e "${Y}ATENÇÃO:${NC} esta configuração libera acesso geral."
    echo "Edite /etc/squid/squid.conf depois para restringir por IP, se quiser."
    read -p "Enter para voltar..." _
}

# --- INSTALAR SSLH NA PORTA 443 ---
install_sslh() {
    cabecalho
    echo -e "${P}>>> INSTALAÇÃO DO SSLH NA PORTA 443${NC}"
    echo "Isso permite usar SSH na porta 443, por exemplo:"
    echo "  ssh -D 1080 -p 443 user@IP_DA_VPS"
    echo "E depois no Firefox usar SOCKS 127.0.0.1:1080 (como você fazia na PM)."
    echo ""

    apt-get update -y >/dev/null 2>&1
    apt-get install -y sslh >/dev/null 2>&1

    if [ -f /etc/default/sslh ]; then
        cp /etc/default/sslh "/etc/default/sslh.bak_$(date +%F_%H%M%S)"
    fi

    cat <<'EOF' >/etc/default/sslh
# PMESP MANAGER - CONFIG SSLH
RUN=yes

DAEMON_OPTS="--user sslh --listen 0.0.0.0:443 \
--ssh 127.0.0.1:22 \
--pidfile /run/sslh/sslh.pid"
EOF

    systemctl enable sslh >/dev/null 2>&1
    systemctl restart sslh

    echo -e "${G}SSLH configurado na porta 443 redirecionando para SSH (22).${NC}"
    echo ""
    echo "Lembre-se de liberar a porta 443 no firewall da VPS (iptables/ufw)."
    read -p "Enter para voltar..." _
}

# --- MONITORAR ACESSOS (PARA CRON) ---
monitorar_acessos() {
    while read -r line; do
        [ -z "$line" ] && continue
        user=$(echo "$line" | jq -r '.usuario' 2>/dev/null)
        [ -z "$user" ] && continue
        [ "$user" = "null" ] && continue

        limite=$(echo "$line" | jq -r '.limite')
        [ -z "$limite" ] && limite=0

        sessoes=$(who | awk -v user="$user" '$1==user {c++} END {print c+0}')

        if [ "$sessoes" -gt 0 ]; then
            echo "$(date '+%F %T') | user=$user | sessoes=$sessoes | limite=$limite" >> "$LOG_MONITOR"

            if [ "$limite" -gt 0 ] && [ "$sessoes" -gt "$limite" ]; then
                echo "$(date '+%F %T') | LIMITE EXCEDIDO: $user (sessoes=$sessoes, limite=$limite)" >> "$LOG_MONITOR"
                # Se quiser derrubar sessões excedentes, descomente a linha abaixo:
                # pkill -KILL -u "$user"
            fi
        fi
    done < "$DB_PMESP"
}

# --- CONFIGURAR CRON PARA MONITORAR ACESSOS ---
configurar_cron_monitor() {
    cabecalho
    echo -e "${C}>>> CONFIGURAR CRON PARA MONITORAR ACESSOS${NC}"
    script_path=$(readlink -f "$0")
    echo "Script atual: $script_path"
    echo ""
    echo "Será criado/atualizado um cron a cada 1 minuto:"
    echo "  */1 * * * * /bin/bash $script_path --cron-monitor"
    echo ""
    read -p "Confirmar? (s/N): " resp
    case "$resp" in
        s|S|y|Y)
            (
                crontab -l 2>/dev/null | grep -v -- "--cron-monitor"
                echo "*/1 * * * * /bin/bash $script_path --cron-monitor >/dev/null 2>&1"
            ) | crontab -
            echo -e "${G}Cron configurado com sucesso.${NC}"
            ;;
        *)
            echo "Cancelado."
            ;;
    esac
    sleep 2
}

# --- MENU PRINCIPAL (NOVO VERTICAL E LIMPO) ---
menu() {
    while true; do
        cabecalho

        echo -e "${C}╭${LINE_H}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${C}╮${NC}"
        echo -e "${C}┃${W}          ${G}🛡️ GESTÃO DE ACESSOS E SISTEMA PMESP V8.0 ${NC}        ${C}┃${NC}"
        echo -e "${C}┣${LINE_H}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┫${NC}"

        # GESTÃO DE USUÁRIOS (Opções separadas)
        echo -e "${C}┃ ${W}${G}01${W} ⮞ CRIAR NOVO USUÁRIO ${C}                                  ┃${NC}"
        echo -e "${C}┃ ${W}${G}02${W} ⮞ LISTAR TODOS OS USUÁRIOS ${C}                            ┃${NC}"
        echo -e "${C}┃ ${W}${G}03${W} ⮞ REMOVER USUÁRIO ${C}                                     ┃${NC}"
        echo -e "${C}┃ ${W}${G}04${W} ⮞ ALTERAR VALIDADE DE USUÁRIO ${C}                         ┃${NC}"
        echo -e "${C}┃ ${W}${G}05${W} ⮞ VISUALIZAR USUÁRIOS VENCIDOS ${C}                        ┃${NC}"
        echo -e "${C}┃ ${W}${G}06${W} ⮞ MONITORAR USUÁRIOS ONLINE (Atualização em 2s) ${C}       ┃${NC}"
        echo -e "${C}┃ ${W}${G}07${W} ⮞ RESETAR SENHA (ENVIO POR EMAIL) ${C}                     ┃${NC}"
        echo -e "${C}┃ ${W}${G}08${W} ⮞ VINCULAR HWID ${C}                                       ┃${NC}"

        echo -e "${C}┣${LINE_H}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┫${NC}"

        # SUPORTE E CONFIGURAÇÃO
        echo -e "${C}┃ ${W}${G}09${W} ⮞ ABRIR NOVO CHAMADO ${C}                                  ┃${NC}"
        echo -e "${C}┃ ${W}${G}10${W} ⮞ GERENCIAR CHAMADOS (Listar/Fechar) ${C}                  ┃${NC}"
        echo -e "${C}┃ ${W}${G}11${W} ⮞ CONFIGURAR SMTP GMAIL ${C}                               ┃${NC}"

        echo -e "${C}┣${LINE_H}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┫${NC}"

        # INSTALAÇÃO E SISTEMA
        echo -e "${C}┃ ${W}${G}12${W} ⮞ INSTALAR DEPENDÊNCIAS BÁSICAS ${C}                       ┃${NC}"
        echo -e "${C}┃ ${W}${G}13${W} ⮞ INSTALAR SQUID PROXY ${C}                                ┃${NC}"
        echo -e "${C}┃ ${W}${G}14${W} ⮞ INSTALAR SSLH (Porta 443) ${C}                           ┃${NC}"
        echo -e "${C}┃ ${W}${G}15${W} ⮞ CONFIGURAR CRON MONITOR (Limite de acesso) ${C}          ┃${NC}"

        echo -e "${C}┣${LINE_H}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┫${NC}"
        echo -e "${C}┃ ${R}00${W} ⮞ SAIR ${C}                                                ┃${NC}"
        echo -e "${C}┗${LINE_H}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛${NC}"

        read -p "${W}➤ ${Y}INFORME UMA OPÇÃO:${NC} " op

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
            *) echo -e "${R}Opção inválida.${NC}"; sleep 1 ;;
        esac
    done
}

# --- MODO CRON (APENAS MONITORAR) ---
if [ "$1" == "--cron-monitor" ]; then
    monitorar_acessos
    exit 0
fi

# --- INÍCIO ---
menu
