#!/bin/bash
# PMESP MANAGER V8.0 - TÁTICO INTEGRADO

DB_PMESP="/etc/pmesp_users.json"
DB_CHAMADOS="/etc/pmesp_tickets.json"
CONFIG_SMTP="/etc/msmtprc"

# Cores
R="\033[1;31m"; G="\033[1;32m"; Y="\033[1;33m"; B="\033[1;34m"; P="\033[1;35m"; C="\033[1;36m"; W="\033[1;37m"; NC="\033[0m"
LINE_H="${C}═${NC}"

cabecalho() {
    clear
    # Contador corrigido: conta as linhas que tem "usuario" no JSON
    _tuser=$(grep -c "\"usuario\":" "$DB_PMESP" 2>/dev/null || echo "0")
    _ons=$(who | grep -v 'root' | wc -l)
    
    echo -e "${C}╭${LINE_H}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${C}╮${NC}"
    echo -e "${C}┃${P}           PMESP MANAGER V8.0 - TÁTICO INTEGRADO           ${C}┃${NC}"
    echo -e "${C}┣${LINE_H}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┫${NC}"
    echo -e "${C}┃ ${Y}TOTAL: ${W}$_tuser ${Y}| ONLINE: ${G}$_ons ${Y}| IP: ${G}$(wget -qO- ipv4.icanhazip.com 2>/dev/null)${C}  ┃${NC}"
    echo -e "${C}┗${LINE_H}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛${NC}"
}

criar_usuario() {
    cabecalho
    echo -e "${G}>>> NOVO CADASTRO DE POLICIAL${NC}"
    read -p "RE: " matricula
    read -p "Email: " email
    read -p "Login: " usuario
    [ -z "$usuario" ] && return
    
    if id "$usuario" >/dev/null 2>&1; then echo -e "${R}Usuário existe!${NC}"; sleep 2; return; fi

    read -p "Senha: " senha
    read -p "Dias: " dias
    read -p "Limite: " limite

    # Cria no Linux
    useradd -M -s /bin/false "$usuario"
    echo "$usuario:$senha" | chpasswd
    data_exp=$(date -d "+$dias days" +"%Y-%m-%d")
    chage -E "$data_exp" "$usuario"

    # Salva no JSON (Garante que o JQ rode aqui)
    if ! command -v jq &> /dev/null; then apt install jq -y; fi

    item=$(jq -n --arg u "$usuario" --arg s "$senha" --arg d "$dias" --arg l "$limite" --arg m "$matricula" --arg e "$email" --arg h "PENDENTE" --arg ex "$data_exp" \
    '{usuario: $u, senha: $s, dias: $d, limite: $l, matricula: $m, email: $e, hwid: $h, expiracao: $ex}')
    echo "$item" >> "$DB_PMESP"

    echo -e "${G}Usuário $usuario criado com sucesso!${NC}"
    sleep 2
}

# --- Adicione as demais funções aqui (Listar, Remover, etc.) conforme os scripts anteriores ---

menu() {
    while true; do
        cabecalho
        echo -e "${C}┃ ${G}01${W} ⮞ CRIAR NOVO USUÁRIO${NC}"
        echo -e "${C}┃ ${R}00${W} ⮞ SAIR${NC}"
        read -p "Opção: " op
        case $op in
            1|01) criar_usuario ;;
            0|00) exit 0 ;;
        esac
    done
}
menu
