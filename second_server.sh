#!/bin/bash

set -e

echo "======================================"
echo "Shadowsocks Second Setup (Chain)"
echo "======================================"
echo ""

if [ "$EUID" -ne 0 ]; then 
    echo "Ошибка: Нужен root"
    exit 1
fi

echo "=== Настройка подключения к основному серверу ==="
echo ""
echo "Введите IP-адрес основного сервера:"
read US_SERVER_IP

echo "Введите порт основного сервера (по умолчанию 8388):"
read US_SERVER_PORT
US_SERVER_PORT=${US_SERVER_PORT:-8388}

echo "Введите пароль от основного сервера:"
read -s US_SERVER_PASSWORD
echo ""

echo ""
echo "=== Настройка сервера для подключения клиентов ==="
echo ""
echo "Порт для клиентов (по умолчанию 8389):"
read CLIENT_PORT
CLIENT_PORT=${CLIENT_PORT:-8389}

echo "Ппароль для клиентов (минимум 8 символов):"
read -s CLIENT_PASSWORD
echo ""
echo "Повторите пароль:"
read -s CLIENT_PASSWORD_CONFIRM
echo ""

if [ "$CLIENT_PASSWORD" != "$CLIENT_PASSWORD_CONFIRM" ]; then
    echo "Ошибка: Пароли не совпадают!"
    exit 1
fi

if [ ${#CLIENT_PASSWORD} -lt 8 ]; then
    echo "Ошибка: Пароль слишком короткий (минимум 8 символов)!"
    exit 1
fi

echo ""
echo "======================================"
echo "Конфигурация:"
echo "======================================"
echo "US сервер: ${US_SERVER_IP}:${US_SERVER_PORT}"
echo "Порт для клиентов: ${CLIENT_PORT}"
echo "Метод шифрования: chacha20-ietf-poly1305"
echo ""
echo "Начинаю установку..."
echo ""

echo "[1/7] Обновление системы..."
apt update -qq
apt upgrade -y -qq

echo "[2/7] Установка Shadowsocks..."
apt install -y -qq shadowsocks-libev wget

echo "[3/7] Создание конфигурации клиента к US..."
mkdir -p /etc/shadowsocks-libev
cat > /etc/shadowsocks-libev/client.json <<EOF
{
    "server":"${US_SERVER_IP}",
    "server_port":${US_SERVER_PORT},
    "local_address":"127.0.0.1",
    "local_port":1080,
    "password":"${US_SERVER_PASSWORD}",
    "timeout":300,
    "method":"chacha20-ietf-poly1305"
}
EOF

echo "[4/7] Установка gost..."
cd /tmp
wget -q https://github.com/ginuerzh/gost/releases/download/v2.11.5/gost-linux-amd64-2.11.5.gz
gunzip -f gost-linux-amd64-2.11.5.gz
chmod +x gost-linux-amd64-2.11.5
mv gost-linux-amd64-2.11.5 /usr/local/bin/gost

echo "[5/7] Создание systemd сервиса для подключения к US..."
cat > /etc/systemd/system/ss-local-us.service <<EOF
[Unit]
Description=Shadowsocks Local Client to US
After=network.target

[Service]
Type=simple
User=root
ExecStart=/usr/bin/ss-local -c /etc/shadowsocks-libev/client.json
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

echo "[6/7] Создание systemd сервиса для gost (цепочка)..."
cat > /etc/systemd/system/gost-proxy.service <<EOF
[Unit]
Description=Gost Proxy Chain
After=network.target ss-local-us.service
Requires=ss-local-us.service

[Service]
Type=simple
User=root
ExecStart=/usr/local/bin/gost -L=ss://chacha20-ietf-poly1305:${CLIENT_PASSWORD}@:${CLIENT_PORT} -F=socks5://127.0.0.1:1080
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

if command -v ufw &> /dev/null; then
    ufw allow ${CLIENT_PORT}/tcp
    ufw allow ${CLIENT_PORT}/udp
    echo "Порт ${CLIENT_PORT} открыт в UFW"
fi
echo "[7/7] Запуск сервисов..."
systemctl daemon-reload
systemctl enable ss-local-us
systemctl enable gost-proxy
systemctl restart ss-local-us
systemctl restart gost-proxy

sleep 3
SS_STATUS=$(systemctl is-active ss-local-us)
GOST_STATUS=$(systemctl is-active gost-proxy)

echo ""
echo "======================================"
if [ "$SS_STATUS" = "active" ] && [ "$GOST_STATUS" = "active" ]; then
    echo "✅ Установка завершена успешно!"
else
    echo "⚠️  Установка завершена с предупреждениями"
fi
echo "======================================"
echo ""
echo "Статус подключения к US:"
systemctl status ss-local-us --no-pager | head -n 5
echo ""
echo "Статус gost (сервер для клиентов):"
systemctl status gost-proxy --no-pager | head -n 5
echo ""
echo "======================================"
echo "Данные для подключения ваших устройств:"
echo "======================================"
echo ""

SERVER_IP=$(curl -s ifconfig.me)

echo "  IP сервера: ${SERVER_IP}"
echo "  Порт: ${CLIENT_PORT}"
echo "  Пароль: ${CLIENT_PASSWORD}"
echo "  Метод: chacha20-ietf-poly1305"
echo ""

SS_STRING="${CLIENT_PASSWORD}"
SS_BASE64=$(echo -n "chacha20-ietf-poly1305:${SS_STRING}" | base64 -w 0)
SS_URL="ss://${SS_BASE64}@${SERVER_IP}:${CLIENT_PORT}#RU-Proxy-Chain"

echo "======================================"
echo "SS ссылка для быстрого импорта:"
echo "======================================"
echo ""
echo "${SS_URL}"
echo ""
echo "Скопируйте эту ссылку и используйте в:"
echo "  • Nekoray: Сервер → Импорт из буфера обмена"
echo "  • Shadowsocks Android: + → Вставить из буфера"
echo "  • v2rayNG: + → Импорт из буфера"
echo "  • Hiddify: Добавить профиль → Вставить"
echo "  • iOS Shadowrocket: + → Вставить из буфера"
echo ""
echo "======================================"
echo "Полезные команды:"
echo "======================================"
echo ""
echo "Проверить статус:"
echo "  sudo systemctl status ss-local-us"
echo "  sudo systemctl status gost-proxy"
echo ""
echo "Посмотреть логи:"
echo "  sudo journalctl -u ss-local-us -f"
echo "  sudo journalctl -u gost-proxy -f"
echo ""
echo "Перезапустить сервисы:"
echo "  sudo systemctl restart ss-local-us"
echo "  sudo systemctl restart gost-proxy"
echo ""

if [ "$SS_STATUS" != "active" ] || [ "$GOST_STATUS" != "active" ]; then
    echo "❌ Некоторые сервисы не запустились. Проверьте логи:"
    echo "  sudo journalctl -u ss-local-us -n 50"
    echo "  sudo journalctl -u gost-proxy -n 50"
    echo ""
fi
