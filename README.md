# Двухсерверная схема Shadowsocks

**Теги:** DIY или Сделай сам, Учебный процесс в IT, Тестирование IT-систем

---

## Проблема

С введением белых списков в России многие столкнулись с проблемой: VPN в России работают нестабильно и постоянно блокируются, из-за DPI (Deep Packet Inspection) невозможно достучаться до серверов в других странах для обхода блокировок YouTube, ChatGPT и других сервисов. Как многие видели, сервисы Яндекса попали в официальные белые списки, тут мне в голову сразу пришла идея о тестировании их облачных решений на раздачу в аренду VPS с ip адресами, находящимися в белых списках. И как выяснилось - да, даже на момент 17 февраля 2026 года всё работает и ip выдаются.

Но тут новая проблема, так как прямое подключение к зарубежному VPS быстро блокируется, а через российский сервер выходить в интернет напрямую — бесполезно из-за тех же блокировок. Пришлось выкручиваться.

## Решение

**Двухсерверная цепочка**: ваше устройство подключается к российскому серверу (который в белых списках, который можно получить только случайно), а он уже проксирует весь трафик на, в моём случае, американский сервер, откуда трафик выходит в интернет без ограничений.

### Схема работы

```
Ваше устройство → RU сервер (Москва) → US сервер → Интернет
                   [белые списки]
```

### Почему Shadowsocks?

- ✅ Легковесный и быстрый
- ✅ Хорошо противостоит DPI
- ✅ Простая настройка
- ✅ Работает на всех платформах
- ✅ Поддержка ss:// ссылок для быстрого импорта

### Что понадобится

- VPS (любой дешёвый, я взял на aeza за 5 евро)
- VPS в России, обязательно Yandex Cloud
- 10 минут времени

---

## Часть 1: Настройка основного сервера

### Автоматическая установка

Я подготовил bash-скрипт, который всё сделает автоматически. Подключитесь к вашему US серверу и выполните:

```bash
wget https://raw.githubusercontent.com/Mr-Zapi/Shadowsocks/blob/main/main_server.sh
chmod +x main_server.sh
sudo bash main_server.sh
```

Скрипт спросит:
- **Пароль** для Shadowsocks (придумайте сложный, минимум 8 символов)
- **Порт** (по умолчанию 8388, можно оставить или указать свой)

### Что делает скрипт

1. Обновляет систему
2. Устанавливает `shadowsocks-libev`
3. Создаёт конфигурацию с методом шифрования `chacha20-ietf-poly1305`
4. Настраивает файрвол (открывает указанный порт)
5. Включает автозапуск сервиса

### Результат

В конце скрипт выведет данные для следующего шага:

```
====================================
✅ Установка завершена успешно!
====================================

Сохраните эти данные для настройки RU сервера:

  IP сервера: ваш_ip
  Порт: 8388
  Пароль: ваш_пароль
  Метод: chacha20-ietf-poly1305
```

### Ручная установка (если не хотите использовать скрипт)

```bash
sudo apt update
sudo apt install shadowsocks-libev -y
sudo nano /etc/shadowsocks-libev/config.json
```

```json
{
    "server":"0.0.0.0",
    "server_port":8388,
    "password":"ваш_сильный_пароль",
    "timeout":300,
    "method":"chacha20-ietf-poly1305",
    "fast_open":true,
    "mode":"tcp_and_udp"
}
```

```bash
sudo systemctl enable shadowsocks-libev
sudo systemctl start shadowsocks-libev
sudo ufw allow 8388
```

---

## Часть 2: Настройка RU сервера (ключевой момент)

Здесь происходит магия: мы создаём цепочку из двух Shadowsocks серверов с помощью инструмента **gost**.

### Архитектура

На российском сервере будут работать два компонента:

1. **ss-local** — Shadowsocks клиент, который подключается к основному серверу и создаёт локальный SOCKS5 прокси (127.0.0.1:1080)
2. **gost** — принимает подключения от ваших устройств на порту 8389 и проксирует их через локальный SOCKS5 на основной сервер

### Автоматическая установка

```bash
wget https://raw.githubusercontent.com/Mr-Zapi/Shadowsocks/blob/main/second_server.sh
chmod +x second_server.sh
sudo bash second_server.sh
```

Скрипт попросит ввести:

**Данные основного сервера:**
- IP-адрес
- Порт (обычно 8388)
- Пароль

**Настройки для клиентов:**
- Порт для подключения (по умолчанию 8389)
- Пароль для ваших устройств

### Что делает скрипт

1. Устанавливает `shadowsocks-libev` и `gost`
2. Создаёт конфиг для подключения к основному серверу
3. Создаёт два systemd сервиса с автозапуском:
   - `ss-local-us.service` — клиент к US
   - `gost-proxy.service` — сервер для ваших устройств
4. Настраивает файрвол
5. Запускает всё и проверяет статус

### Результат

```
====================================
✅ Установка завершена успешно!
====================================

Данные для подключения ваших устройств:

  IP сервера: ваш_ip
  Порт: 8389
  Пароль: ваш_пароль_для_клиентов
  Метод: chacha20-ietf-poly1305

SS ссылка для быстрого импорта:
ss://Y2hhY2hhM...#RU-Chain
```

### Ручная установка RU сервера

```bash
sudo apt update
sudo apt install shadowsocks-libev wget -y
sudo nano /etc/shadowsocks-libev/client.json
```

```json
{
    "server":"ip_основного_сервера",
    "server_port":8388,
    "local_address":"127.0.0.1",
    "local_port":1080,
    "password":"пароль",
    "timeout":300,
    "method":"chacha20-ietf-poly1305"
}
```

```bash
wget https://github.com/ginuerzh/gost/releases/download/v2.11.5/gost-linux-amd64-2.11.5.gz
gunzip gost-linux-amd64-2.11.5.gz
chmod +x gost-linux-amd64-2.11.5
sudo mv gost-linux-amd64-2.11.5 /usr/local/bin/gost
sudo nano /etc/systemd/system/ss-local-us.service
```

```ini
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
```

```bash
sudo nano /etc/systemd/system/gost-proxy.service
```

```ini
[Unit]
Description=Gost Proxy Chain
After=network.target ss-local-us.service
Requires=ss-local-us.service

[Service]
Type=simple
User=root
ExecStart=/usr/local/bin/gost -L=ss://chacha20-ietf-poly1305:ваш_пароль@:8389 -F=socks5://127.0.0.1:1080
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
```

```bash
sudo systemctl daemon-reload
sudo systemctl enable ss-local-us gost-proxy
sudo systemctl start ss-local-us gost-proxy
sudo ufw allow 8389
```

---

## Часть 3: Подключение клиентов

Теперь самое приятное — подключение ваших устройств.

### Linux (Nekoray)

**Установка:**

```bash
wget https://github.com/MatsuriDayo/nekoray/releases/download/3.26/nekoray-3.26-2023-12-09-linux64.zip
unzip nekoray-*.zip
cd nekoray
./nekoray
```

**Настройка:**

**Способ 1: Импорт по ссылке**
1. Скопируйте ss:// ссылку из вывода скрипта
2. `Сервер → Импорт из буфера обмена`
3. Готово!

**Способ 2: Ручная настройка**
1. `Сервер → Новый профиль`
2. Тип: **Shadowsocks**
3. Заполните:
   - **Адрес**: IP вашего RU сервера
   - **Порт**: 8389
   - **Пароль**: пароль для клиентов
   - **Метод**: chacha20-ietf-poly1305
4. `OK → Старт`

### Android

**Shadowsocks Android** (оригинальный клиент)
- [GitHub Releases](https://github.com/shadowsocks/shadowsocks-android/releases)
- Импорт: `+` → Сканировать QR код или `Вставить из буфера`

### Windows

**Hiddify**
- Универсален, написан на Flutter, используется не только в Windows системах, просто хотел сюда что-то отдельно поместить :3

---

## Управление и мониторинг

### Проверка статуса на RU сервере

```bash
sudo systemctl status ss-local-us
sudo systemctl status gost-proxy

# Логи в реальном времени
sudo journalctl -u ss-local-us -f
sudo journalctl -u gost-proxy -f

# Проверка портов
sudo netstat -tlnp | grep -E '1080|8389'
```

### Проверка работы цепочки

На RU сервере:

```bash
# Проверить что подключение к US работает
curl --socks5 127.0.0.1:1080 ifconfig.me
# По сути, должен отдать ip основного сервера
```

### Перезапуск сервисов

```bash
sudo systemctl restart ss-local-us
sudo systemctl restart gost-proxy
```

---

## Производительность и скорость

### Тесты скорости

В моём тесте (VPS в Москве → VPS в США) исходя из моего тарифного плана в 100 Мбит/c:

- **Пинг**: ~150-350ms (Москва-США)
- **Скорость загрузки**: ~80-90 Мбит/с
- **Скорость отдачи**: ~70-90 Мбит/с

---

## Безопасность

### Рекомендации

**1. Используйте сильные пароли**

```bash
# Генерация случайного пароля
openssl rand -base64 16
```

**2. Смените порты с дефолтных**

```
MAIN сервер: 8388 → выберите случайный 10000-65535
RU сервер: 8389 → выберите случайный 10000-65535
```

**3. Ограничьте доступ по IP (если у вас статический IP)**

На MAIN сервере (разрешить только с RU):

```bash
sudo ufw default deny incoming
sudo ufw allow from ваш_русский_ip to any port 8388
sudo ufw enable
```

На RU сервере (разрешить только с вашего IP):

```bash
sudo ufw default deny incoming
sudo ufw allow from ВАШ_IP to any port 8389
sudo ufw allow 22  # SSH
sudo ufw enable
```

**4. Включите fail2ban (защита от брутфорса SSH):**

```bash
sudo apt install fail2ban -y
sudo systemctl enable fail2ban
```

**5. Регулярно обновляйте систему**

```bash
sudo apt update && sudo apt upgrade -y
```

### Почему это безопасно?

- ✅ Трафик между серверами шифруется Shadowsocks
- ✅ DPI не видит реальное содержимое трафика
- ✅ Ваш провайдер видит только подключение к российскому серверу
- ✅ chacha20-ietf-poly1305 — современный безопасный шифр

---

## Устранение проблем

### Сервис не запускается

```bash
# Посмотрите логи
sudo journalctl -u ss-local-us -n 50
sudo journalctl -u gost-proxy -n 50

# Типичные проблемы:
# 1. Порт занят → смените порт в конфиге
# 2. Неверный пароль → проверьте пароль MAIN сервера
# 3. MAIN недоступен → проверьте firewall
```

### Подключается, но не работает

```bash
# На RU сервере проверьте цепочку
curl --socks5 127.0.0.1:1080 ifconfig.me

# Если не работает:
# 1. Проверьте что ss-local подключён к основному серверу
sudo systemctl status ss-local-us

# 2. Проверьте что gost работает
sudo systemctl status gost-proxy

# 3. Проверьте порты
sudo netstat -tlnp | grep -E '1080|8389'
```

### "Connection refused" на клиенте

- Проверьте что gost запущен: `sudo systemctl status gost-proxy`
- Проверьте файрвол на RU: `sudo ufw status`
- Проверьте что используете правильный пароль

---

## Стоимость решения

### Минимальная конфигурация:

**RU VPS (2GB RAM): 980₽/месяц** Yandex Cloud

Ресурсы:
- Платформа Intel Cascade Lake
- Гарантированная доля vCPU 5%
- vCPU 2
- RAM 2 ГБ
- Объём дискового пространства 15 ГБ

**US VPS (1GB RAM): €4.94/месяц** AEZA

Тариф CLTs-1:
- Система Ubuntu 20.04
- Процессор 1 cores
- RAM 2 GB
- Хранилище 30 GB

**Итого: ~1600₽**

---

## Благодарности

Спасибо комьюнити Shadowsocks и разработчикам gost за отличные инструменты!

---
