#!/bin/bash

# Ссылка на тестовое видео (любое стабильное видео без ограничений)
TEST_VIDEO_URL="https://www.youtube.com/watch?v=kJQP7kiw5Fk&list=RDkJQP7kiw5Fk&start_radio=1&pp=ygUKZGVzcGFjaXRvIKAHAQ%3D%3D"
TEST_QUEUE=2
TEST_UID=2000 # Наш пользователь tester из Dockerfile

# Ваша 100% рабочая стратегия
INIT_STRATEGY="--filter-tcp=443 --payload=tls_client_hello --lua-desync=fakeddisorder:pos=midsld:tcp_seq=1000000"

# Вариации вашей стратегии для поиска максимальной скорости
STRATEGIES="
--filter-tcp=443 --payload=tls_client_hello --lua-desync=fakeddisorder:pos=midsld:tcp_seq=1000000
--filter-tcp=443 --payload=tls_client_hello --lua-desync=fakeddisorder:pos=midsld:tcp_seq=2000000
--filter-tcp=443 --payload=tls_client_hello --lua-desync=fakeddisorder:pos=1:tcp_seq=1000000
--filter-tcp=443 --payload=tls_client_hello --lua-desync=fakeddisorder:pos=midsld:tcp_seq=1000000 --dpi-desync-fooling=badsum
--filter-tcp=443 --payload=tls_client_hello --lua-desync=fakeddisorder:pos=midsld:tcp_seq=1000000 --dpi-desync-fooling=md5sig
--filter-tcp=443 --payload=tls_client_hello --lua-desync=fakeddisorder:pos=host:tcp_seq=1000000 --dpi-desync-fooling=badsum
"

echo "=== СТАРТ ИСПРАВЛЕННОГО ЛУА-АВТОТЕСТА ZAPRET2 ==="

# Очищаем старые правила iptables на случай, если они зависли после Ctrl+C
iptables -t mangle -F OUTPUT 2>/dev/null

# -------------------------------------------------------------------------
# ШАГ 1: Запуск nfqws2 для yt-dlp (Изоляция строго по UID пользователя tester)
# -------------------------------------------------------------------------
echo "[*] Запуск эталонного обхода для yt-dlp..."
nfqws2 --queue-num=$TEST_QUEUE $INIT_STRATEGY > /dev/null 2>&1 &
INIT_PID=$!
sleep 1.5

# Включаем iptables ТОЛЬКО для пользователя tester
iptables -t mangle -A OUTPUT -p tcp -m owner --uid-owner $TEST_UID -m multiport --dports 80,443 -j NFQUEUE --queue-num $TEST_QUEUE

echo "[+] Запрос живой ссылки у YouTube (запускаем от пользователя tester)..."
# Выполняем yt-dlp от имени tester, чтобы его трафик пошел в nfqws2
LIVE_STREAM_URL=$(su tester -c "yt-dlp -g -f 'bv*[height<=720]' '$TEST_VIDEO_URL'" | head -n 1)

# Снимаем временное правило и гасим стартовый процесс
iptables -t mangle -D OUTPUT -p tcp -m owner --uid-owner $TEST_UID -m multiport --dports 80,443 -j NFQUEUE --queue-num $TEST_QUEUE
kill $INIT_PID
wait $INIT_PID 2>/dev/null

if [ -z "$LIVE_STREAM_URL" ]; then
    echo "[-] Критическая ошибка: Не удалось получить ссылку. Проверьте параметры fakeddisorder."
    exit 1
fi
echo "[+] Ссылка успешно получена!"

# -------------------------------------------------------------------------
# ШАГ 2: Перебор модификаций стратегии на скачивание медиа-чанка (curl)
# -------------------------------------------------------------------------
IFS="
"
echo "$STRATEGIES" | while read -r STRATEGY; do
    [ -z "$STRATEGY" ] && continue
    
    echo "----------------------------------------"
    echo "[*] Тестируем стратегию: $STRATEGY"

    # Запуск тестового инстанса nfqws2
    nfqws2 --queue-num=$TEST_QUEUE $STRATEGY > /dev/null 2>&1 &
    NFQWS_PID=$!
    sleep 1.5

    # Включаем iptables для пользователя tester
    iptables -t mangle -A OUTPUT -p tcp -m owner --uid-owner $TEST_UID -m multiport --dports 80,443 -j NFQUEUE --queue-num $TEST_QUEUE

    # Тест скачивания чанка (6 секунд) через curl от имени tester
    echo "[+] Запускаем скачивание медиа-чанка через curl (6 сек)..."
    DOWNLOAD_RESULT=$(su tester -c "curl -o /dev/null -s -w '%{http_code},%{speed_download}' --max-time 6 '$LIVE_STREAM_URL'")
    
    HTTP_CODE=$(echo "$DOWNLOAD_RESULT" | cut -d',' -f1)
    SPEED_BYTES=$(echo "$DOWNLOAD_RESULT" | cut -d',' -f2)
    
    [ -z "$SPEED_BYTES" ] && SPEED_BYTES=0
    SPEED_KBPS=$((SPEED_BYTES * 8 / 1024))

    # Выключаем iptables для этой итерации
    iptables -t mangle -D OUTPUT -p tcp -m owner --uid-owner $TEST_UID -m multiport --dports 80,443 -j NFQUEUE --queue-num $TEST_QUEUE

    kill $NFQWS_PID
    wait $NFQWS_PID 2>/dev/null

    # Вывод результатов
    if [ "$HTTP_CODE" = "200" ] && [ "$SPEED_KBPS" -gt 2000 ]; then
        echo "[+] РЕЗУЛЬТАТ: ОТЛИЧНО! HTTP $HTTP_CODE | Скорость: ${SPEED_KBPS} Кбит/с"
    elif [ "$HTTP_CODE" = "200" ]; then
        echo "[!] РЕЗУЛЬТАТ: Соединение установлено, но скорость задушена: ${SPEED_KBPS} Кбит/с"
    else
        echo "[-] РЕЗУЛЬТАТ: БЛОКИРОВКА / ТАЙМАУТ. HTTP код: $HTTP_CODE (Скорость: ${SPEED_KBPS} Кбит/с)"
    fi
done

echo "========================================"
echo "=== ТЕСТИРОВАНИЕ СТРАТЕГИЙ ЗАВЕРШЕНО ==="
