#!/bin/bash

# Ссылка на тестовое видео (любое стабильное видео без ограничений)
TEST_URL="https://www.youtube.com/watch?v=kJQP7kiw5Fk&list=RDkJQP7kiw5Fk&start_radio=1&pp=ygUKZGVzcGFjaXRvIKAHAQ%3D%3D"
TEST_QUEUE=2

# Строго ОДНА ваша проверенная стратегия с явным подключением библиотек Lua
STRATEGY="--lua-init=@/opt/zapret2/lua/zapret-lib.lua --filter-tcp=443 --payload=tls_client_hello --lua-desync=fakeddisorder:pos=midsld:tcp_seq=1000000"

echo "=== СТАРТ ФОКУСНОГО ТЕСТА ВАШЕЙ СТРАТЕГИИ ==="

# 1. Фиксируем сетевое правило в ядре
iptables -t mangle -F OUTPUT 2>/dev/null
iptables -t mangle -A OUTPUT -p tcp --dport 443 -j NFQUEUE --queue-num $TEST_QUEUE

echo "[*] ЗАПУСК NFQWS2 С ВАШИМ LUA-ПРОФИЛЕМ..."

# 2. Запускаем nfqws2 (теперь он найдет файлы Lua-инициализации!)
nfqws2 --qnum=$TEST_QUEUE $STRATEGY > /tmp/nfqws_last_error.log 2>&1 &
NFQWS_PID=$!

# Даем Lua-скриптам время подгрузиться в память
sleep 2

# Проверяем, выжил ли процесс
if ! kill -0 $NFQWS_PID 2>/dev/null; then
    echo "[-] Критическая ошибка: nfqws2 упал при старте!"
    echo "    Лог ошибки: $(cat /tmp/nfqws_last_error.log)"
    iptables -t mangle -F OUTPUT 2>/dev/null
    exit 1
fi

echo "[+] Замер скорости скачивания медиа-файла (6 сек)..."
DOWNLOAD_RESULT=$(curl -o /dev/null -s -w "%{http_code},%{speed_download}" --max-time 6 "$TEST_URL")

HTTP_CODE=$(echo "$DOWNLOAD_RESULT" | cut -d',' -f1)
SPEED_BYTES=$(echo "$DOWNLOAD_RESULT" | cut -d',' -f2)

# 3. Чистим процессы и ядро
kill $NFQWS_PID
wait $NFQWS_PID 2>/dev/null
iptables -t mangle -F OUTPUT 2>/dev/null

[ -z "$SPEED_BYTES" ] && SPEED_BYTES=0
SPEED_KBPS=$((SPEED_BYTES * 8 / 1024))

echo "----------------------------------------"
if [ "$HTTP_CODE" = "200" ]; then
    echo "[+] УСПЕХ! Ваша Lua-стратегия работает корректно."
    echo "[+] РЕАЛЬНАЯ СКОРОСТЬ КАНАЛА: ${SPEED_KBPS} Кбит/с"
else
    echo "[-] БЛОКИРОВКА ИЛИ СЕТЕВОЙ СБОЙ (HTTP код: $HTTP_CODE)"
fi
echo "========================================"
