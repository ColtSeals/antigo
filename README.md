# antigo







wget -qO- https://raw.githubusercontent.com/ColtSeals/antigo/main/install.sh | bash



sudo apt-get update && sudo apt-get install -y curl && \
curl -sSL https://raw.githubusercontent.com/ColtSeals/antigo/refs/heads/main/xray.sh -o xray.sh && \
chmod +x xray.sh && \
mkdir -p /var/log/xray && \
chown -R nobody:nogroup /var/log/xray && \
chmod -R 755 /var/log/xray && \
sudo ./xray.sh
