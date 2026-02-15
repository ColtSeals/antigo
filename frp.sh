#!/bin/bash

# 1. Definir Versão e Arquitetura
FRP_VERSION="0.54.0"
ARCH="linux_amd64"

# 2. Baixar e Instalar
cd /root
wget https://github.com/fatedier/frp/releases/download/v${FRP_VERSION}/frp_${FRP_VERSION}_${ARCH}.tar.gz
tar -zxvf frp_${FRP_VERSION}_${ARCH}.tar.gz
mv frp_${FRP_VERSION}_${ARCH} frp
cd frp
cp frps /usr/bin/
mkdir -p /etc/frp

# 3. Criar Arquivo de Configuração (Servidor)
# bindPort = 443 (Onde o PC da empresa vai conectar)
cat <<EOF > /etc/frp/frps.toml
bindPort = 443
auth.method = "token"
auth.token = "PolicialSP2026"

# Painel opcional para ver status (acesso via browser na porta 7500)
webServer.addr = "0.0.0.0"
webServer.port = 7500
webServer.user = "admin"
webServer.password = "admin"
EOF

# 4. Criar Serviço no Systemd (Para rodar sozinho e reiniciar se cair)
cat <<EOF > /etc/systemd/system/frps.service
[Unit]
Description=FRP Server Service
After=network.target

[Service]
Type=simple
User=root
ExecStart=/usr/bin/frps -c /etc/frp/frps.toml
Restart=on-failure
RestartSec=5s

[Install]
WantedBy=multi-user.target
EOF

# 5. Ativar e Rodar
systemctl daemon-reload
systemctl enable frps
systemctl restart frps

# 6. Liberar Firewall (UFW) se estiver ativo
ufw allow 443/tcp
ufw allow 1010/tcp
ufw allow 7500/tcp

echo "=========================================="
echo "✅ VPS CONFIGURADA COM SUCESSO!"
echo "O servidor FRP está rodando na porta 443."
echo "Sua senha (Token) é: PolicialSP2026"
echo "=========================================="
