#!/bin/bash

# Ссылка на тестовое видео (любое стабильное видео без ограничений)
TEST_VIDEO_URL="https://www.youtube.com/watch?v=kJQP7kiw5Fk&list=RDkJQP7kiw5Fk&start_radio=1&pp=ygUKZGVzcGFjaXRvIKAHAQ%3D%3D"
TEST_QUEUE=2
TEST_UID=2000 # Наш пользователь tester из Dockerfile

# Массив актуальных стратегий под синтаксис nfqws2
declare -a STRATEGIES=(
    "--dpi-desync=split --tcpseg=split:2"
    "--dpi-desync=disorder --tcpseg=disorder:2"
    "--dpi-desync=split --tcpseg=split:2 --dpi-desync-fooling=badsum --fake=1"
    "--dpi-desync=disorder --tcpseg=disorder:2 --dpi-desync-fooling=badsum --fake=1"
    "--dpi-desync=split --tcpseg=split:1 --dpi-desync-fooling=md5sig --fake=1"
    "--dpi-desync=disorder --tcpseg=disorder:2 --fake-with-sni=://google.com --dpi-desync-fooling=badsum"
)

echo "=== СТАРТ МИКРО-АВТОТЕСТА ZAPRET2 (ALPINE) ==="

# 1. Запрашиваем ссылку у yt-dlp
echo "[+] Шаг 1: Запрос живой ссылки у YouTube через yt-dlp..."
LIVE_STREAM_URL=$(yt-dlp -g -f "bv*[height<=720]" "$TEST_VIDEO_URL" | head -n 1)

if [ -z "$LIVE_STREAM_URL" ]; then
    echo "[-] Ошибка: yt-dlp не смог получить прямую ссылку."
    exit 1
fi
echo "[+] Ссылка успешно получена."

# Перебор стратегий
for i in $(seq 0 $((${#STRATEGIES[@]} - 1))); do
    STRATEGY="${STRATEGIES[$i]}"
    echo "----------------------------------------"
    echo "[*] Тестируем стратегию [$i]: $STRATEGY"

    # 2. Запуск nfqws2 в фоне на тестовой очереди
    nfqws2 --queue-num=$TEST_QUEUE $STRATEGY > /dev/null 2>&1 &
    NFQWS_PID=$!
    sleep 1

    # 3. iptables: изолируем трафик по UID пользователя tester (2000)
    iptables -t mangle -A OUTPUT -p tcp -m owner --uid-owner $TEST_UID -m multiport --dports 80,443 -j NFQUEUE --queue-num $TEST_QUEUE

    # 4. Тест скачивания чанка (6 секунд) от имени пользователя tester
    echo "[+] Запускаем скачивание медиа-чанка через curl (6 сек)..."
    DOWNLOAD_RESULT=$(su tester -c "curl -o /dev/null -s -w '%{http_code},%{speed_download}' --max-time 6 '$LIVE_STREAM_URL'")
    
    HTTP_CODE=$(echo $DOWNLOAD_RESULT | cut -d',' -f1)
    SPEED_BYTES=$(echo $DOWNLOAD_RESULT | cut -d',' -f2)
    SPEED_KBPS=$((SPEED_BYTES * 8 / 1024))

    # 5. Чистим iptables
    iptables -t mangle -D OUTPUT -p tcp -m owner --uid-owner $TEST_UID -m multiport --dports 80,443 -j NFQUEUE --queue-num $TEST_QUEUE

    # 6. Гасим nfqws2
    kill $NFQWS_PID
    wait $NFQWS_PID 2>/dev/null

    # Вывод результатов
    if [ "$HTTP_CODE" == "200" ] && [ "$SPEED_KBPS" -gt 1000 ]; then
        echo "[+] РЕЗУЛЬТАТ: УСПЕХ! HTTP $HTTP_CODE | Скорость: ${SPEED_KBPS} Кбит/с"
    elif [ "$HTTP_CODE" == "200" ]; then
        echo "[!] РЕЗУЛЬТАТ: Задушено. HTTP 200, но скорость: ${SPEED_KBPS} Кбит/с"
    else
        echo "[-] РЕЗУЛЬТАТ: БЛОКИРОВКА. HTTP код: $HTTP_CODE (Скорость: ${SPEED_KBPS} Кбит/с)"
    fi
done

echo "========================================"
echo "=== ТЕСТИРОВАНИЕ СТРАТЕГИЙ ЗАВЕРШЕНО ==="
