#!/bin/bash

# Ссылка на тестовое видео (любое стабильное видео без ограничений)
TEST_VIDEO_URL="https://www.youtube.com/watch?v=kJQP7kiw5Fk&list=RDkJQP7kiw5Fk&start_radio=1&pp=ygUKZGVzcGFjaXRvIKAHAQ%3D%3D"
TEST_QUEUE=2

# Несколько стратегий для проверки (базовые примеры nfqws)
declare -a STRATEGIES=(
    "--split-at-host --disorder"
    "--split-at-host --oob"
    "--fake-with-sni=://google.com --split-at-host"
)

echo "=== ЗАПУСК ИЗОЛИРОВАННОГО АВТОТЕСТА ==="

# 1. Получаем живую ссылку через yt-dlp
echo "[+] Шаг 1: Запрос живой ссылки у YouTube через yt-dlp..."
LIVE_STREAM_URL=$(yt-dlp -g -f "bv*[height<=720]" "$TEST_VIDEO_URL" | head -n 1)

if [ -z "$LIVE_STREAM_URL" ]; then
    echo "[-] Ошибка: yt-dlp не смог получить прямую ссылку."
    exit 1
fi
echo "[+] Ссылка успешно получена."

# Перебор стратегий
for i in "${!STRATEGIES[@]}"; do
    STRATEGY="${STRATEGIES[$i]}"
    echo "----------------------------------------"
    echo "[*] Тестируем стратегию [$i]: $STRATEGY"

    # 2. Запуск тестового nfqws
    nfqws --queue-num=$TEST_QUEUE $STRATEGY > /dev/null 2>&1 &
    NFQWS_PID=$!
    sleep 1

    # 3. iptables: заворачиваем трафик ТОЛЬКО этого bash-скрипта (по его PID)
    iptables -t mangle -A OUTPUT -p tcp -m owner --pid-owner $$ -m multiport --dports 80,443 -j NFQUEUE --queue-num $TEST_QUEUE

    # 4. Замеряем скорость скачивания куска видео (тест длится 5 секунд)
    echo "[+] Запускаем скачивание медиа-чанка (5 сек)..."
    DOWNLOAD_RESULT=$(curl -o /dev/null -s -w "%{http_code},%{speed_download}" --max-time 5 "$LIVE_STREAM_URL")
    
    HTTP_CODE=$(echo $DOWNLOAD_RESULT | cut -d',' -f1)
    SPEED_BYTES=$(echo $DOWNLOAD_RESULT | cut -d',' -f2)
    SPEED_KBPS=$((SPEED_BYTES * 8 / 1024))

    # 5. Чистим iptables сразу после curl
    iptables -t mangle -D OUTPUT -p tcp -m owner --pid-owner $$ -m multiport --dports 80,443 -j NFQUEUE --queue-num $TEST_QUEUE

    # 6. Останавливаем nfqws
    kill $NFQWS_PID
    wait $NFQWS_PID 2>/dev/null

    # Вывод результатов итерации
    if [ "$HTTP_CODE" == "200" ]; then
        echo "[+] РЕЗУЛЬТАТ: Успешно! HTTP $HTTP_CODE | Скорость: ${SPEED_KBPS} Кбит/с"
    else
        echo "[-] РЕЗУЛЬТАТ: Ошибка/Блокировка. HTTP код: $HTTP_CODE"
    fi
done

echo "========================================"
echo "=== ТЕСТИРОВАНИЕ СТРАТЕГИЙ ЗАВЕРШЕНО ==="
