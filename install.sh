#!/bin/bash
# Instalador PMESP Manager via GitHub
# Repositório: ColtSeals/antigo

echo -e "\033[1;34m>>> BAIXANDO O GESTOR PMESP...\033[0m"

# 1. Garante que o wget está instalado
apt-get update -y >/dev/null 2>&1
apt-get install wget -y >/dev/null 2>&1

# 2. Define onde o arquivo vai ficar (Pasta binária global)
# Isso permite que você digite apenas 'pmesp' no terminal depois
CAMINHO="/usr/local/bin/pmesp"

# 3. Baixa o código 'manager.sh' do seu repositório (Link RAW)
# Nota: Estou assumindo que a branch principal é 'main'
wget -qO "$CAMINHO" "https://raw.githubusercontent.com/ColtSeals/antigo/main/manager.sh"

# 4. Dá permissão de execução
chmod +x "$CAMINHO"

echo -e "\033[1;32m>>> INSTALAÇÃO CONCLUÍDA!\033[0m"
echo -e "Para abrir o painel, digite apenas: \033[1;33mpmesp\033[0m"
sleep 2

# 5. Executa o painel agora
pmesp
