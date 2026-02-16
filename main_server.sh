#!/bin/bash

set -e

echo "======================================"
echo "Shadowsocks US Server Setup"
echo "======================================"
echo ""

if [ "$EUID" -ne 0 ]; then 
    echo "Ошибка: Нужен root"
    exit 1
fi

echo "Введите пароль для Shadowsocks (минимум 8 символов):"
read -s SS_PASSWORD
echo ""
echo "Повторите пароль:"
read -s SS_PASSWORD_CONFIRM
echo ""

if [ "$SS_PASSWORD" != "$SS_PASSWORD_CONFIRM" ]; then
    echo "Ошибка: Пароли не совпадают!"
    exit 1
fi

if [ ${#SS_PASSWORD} -lt 8 ]; then
    echo "Ошибка: Пароль слишком короткий!"
    exit 1
fi

# Выбор порта
echo "Введите порт для Shadowsocks (по умолчанию 8388):"
read SS_PORT
SS_PORT=${SS_PORT:-8388}

echo ""
echo "======================================"
echo "Конфигурация:"
echo "======================================"
echo "Порт: $SS_PORT"
echo "Метод шифрования: chacha20-ietf-poly1305"
echo ""
echo "Начинаю установку..."
echo ""

echo "[1/5] Обновление системы..."
apt update -qq
apt upgrade -y -qq

echo "[2/5] Установка Shadowsocks..."
apt install -y -qq shadowsocks-libev

echo "[3/5] Создание конфигурации..."
cat > /etc/shadowsocks-libev/config.json <<EOF
{
    "server":"0.0.0.0",
    "server_port":${SS_PORT},
    "password":"${SS_PASSWORD}",
    "timeout":300,
    "method":"chacha20-ietf-poly1305",
    "fast_open":true,
    "mode":"tcp_and_udp"
}
EOF

echo "[4/5] Настройка файрвола..."
if command -v ufw &> /dev/null; then
    ufw allow ${SS_PORT}/tcp
    ufw allow ${SS_PORT}/udp
    echo "Порт ${SS_PORT} открыт в UFW"
fi

echo "[5/5] Запуск Shadowsocks..."
systemctl enable shadowsocks-libev
systemctl restart shadowsocks-libev

sleep 2
if systemctl is-active --quiet shadowsocks-libev; then
    echo ""
    echo "======================================"
    echo "✅ Установка завершена успешно!"
    echo "======================================"
    echo ""
    echo "Сохраните эти данные для настройки RU сервера:"
    echo ""
    echo "  IP сервера: $(curl -s ifconfig.me)"
    echo "  Порт: ${SS_PORT}"
    echo "  Пароль: ${SS_PASSWORD}"
    echo "  Метод: chacha20-ietf-poly1305"
    echo ""
    echo "Статус сервера:"
    systemctl status shadowsocks-libev --no-pager | head -n 5
    echo ""
    echo "Логи можно смотреть командой:"
    echo "  sudo journalctl -u shadowsocks-libev -f"
    echo ""
else
    echo ""
    echo "❌ Ошибка: Shadowsocks не запустился!"
    echo "Проверьте логи: sudo journalctl -u shadowsocks-libev -n 50"
    exit 1
fi
