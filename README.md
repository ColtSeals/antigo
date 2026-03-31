# antigo







wget -qO- https://raw.githubusercontent.com/ColtSeals/antigo/main/install.sh | bash



curl -fsSL https://raw.githubusercontent.com/ColtSeals/antigo/refs/heads/main/xray.sh -o xray_manager.sh && chmod +x xray_manager.sh && sudo bash xray_manager.sh

sudo chown -R nobody /var/log/xray && sudo systemctl restart xray

sudo ./xray_manager.sh






curl -fsSL https://raw.githubusercontent.com/ColtSeals/antigo/refs/heads/main/xxray.sh -o xray_manager.sh && chmod +x xray_manager.sh && sudo bash xray_manager.sh

sudo chown -R nobody /var/log/xray && sudo systemctl restart xray

sudo ./xray_manager.sh
