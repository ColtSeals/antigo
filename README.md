# antigo







wget -qO- https://raw.githubusercontent.com/ColtSeals/antigo/main/install.sh | bash



curl -fsSL https://raw.githubusercontent.com/ColtSeals/antigo/refs/heads/main/xray.sh -o xray_manager.sh && chmod +x xray_manager.sh && sudo bash xray_manager.sh

sudo chown -R nobody /var/log/xray && sudo systemctl restart xray

sudo ./xray_manager.sh






curl -fsSL https://raw.githubusercontent.com/ColtSeals/antigo/refs/heads/main/xxray.sh -o xray_manager.sh && chmod +x xray_manager.sh && sudo bash xray_manager.sh

sudo chown -R nobody /var/log/xray && sudo systemctl restart xray

sudo ./xray_manager.sh




curl -s https://api.ipify.org
(Isso vai mostrar o IP da sua operadora local, tipo aquele 201.55.56.103 de antes).

Teste 2: Testando o túnel via SOCKS5

DOS
curl -s -x socks5://127.0.0.1:10808 https://api.ipify.org
Teste 3: Testando o túnel via HTTP

DOS
curl -s -x http://127.0.0.1:10808 https://api.ipify.org
