#!/bin/bash

# Ссылка на тестовое видео (любое стабильное видео без ограничений)
TEST_VIDEO_URL="https://www.youtube.com/watch?v=kJQP7kiw5Fk&list=RDkJQP7kiw5Fk&start_radio=1&pp=ygUKZGVzcGFjaXRvIKAHAQ%3D%3D"
TEST_QUEUE=2

# Массив актуальных стратегий под синтаксис nfqws2 (Zapret2)
# Каждая строка — это готовый набор параметров для тестирования
declare -a STRATEGIES=(
    # 1. Классический split (рассечение сессии на начальных этапах)
    "--dpi-desync=split --tcpseg=split:2"
    
    # 2. Disorder (изменение порядка следования пакетов для запутывания DPI)
    "--dpi-desync=disorder --tcpseg=disorder:2"
    
    # 3. Split + Fake (подмешивание ложного TLS-хендшейка с "дурением" по контрольной сумме)
    "--dpi-desync=split --tcpseg=split:2 --dpi-desync-fooling=badsum --fake=1"
    
    # 4. Disorder + Fake (комбинация изменения порядка и ложного пакета)
    "--dpi-desync=disorder --tcpseg=disorder:2 --dpi-desync-fooling=badsum --fake=1"
    
    # 5. Агрессивный split на 1-м байте с фейком (часто пробивает жесткие ТСПУ)
    "--dpi-desync=split --tcpseg=split:1 --dpi-desync-fooling=md5sig --fake=1"
    
    # 6. Стратегия Fake + Disorder со специфичным SNI для обманного пакета
    "--dpi-desync=disorder --tcpseg=disorder:2 --fake-with-sni=://google.com --dpi-desync-fooling=badsum"
)

echo "=== СТАРТ ПОЛНОЦЕННОГО АВТОТЕСТА ZAPRET2 ==="

# 1. Запрашиваем ссылку у yt-dlp
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

    # 2. Запуск nfqws2 в фоне на тестовой очереди
    nfqws2 --queue-num=$TEST_QUEUE $STRATEGY > /dev/null 2>&1 &
    NFQWS_PID=$!
    sleep 1.5 # Даем процессу гарантированно инициализироваться

    # 3. iptables: изолируем трафик по PID текущего bash-скрипта ($$)
    iptables -t mangle -A OUTPUT -p tcp -m owner --pid-owner $$ -m multiport --dports 80,443 -j NFQUEUE --queue-num $TEST_QUEUE

    # 4. Тест реального скачивания медиа-чанка (6 секунд)
    echo "[+] Запускаем скачивание медиа-чанка через curl (6 сек)..."
    DOWNLOAD_RESULT=$(curl -o /dev/null -s -w "%{http_code},%{speed_download}" --max-time 6 "$LIVE_STREAM_URL")
    
    HTTP_CODE=$(echo $DOWNLOAD_RESULT | cut -d',' -f1)
    SPEED_BYTES=$(echo $DOWNLOAD_RESULT | cut -d',' -f2)
    SPEED_KBPS=$((SPEED_BYTES * 8 / 1024)) # Конвертируем в Кбит/с

    # 5. Мгновенно чистим за собой iptables, чтобы не копить правила
    iptables -t mangle -D OUTPUT -p tcp -m owner --pid-owner $$ -m multiport --dports 80,443 -j NFQUEUE --queue-num $TEST_QUEUE

    # 6. Гасим текущий инстанс nfqws2
    kill $NFQWS_PID
    wait $NFQWS_PID 2>/dev/null

    # Вывод результатов итерации
    if [ "$HTTP_CODE" == "200" ] && [ "$SPEED_KBPS" -gt 1000 ]; then
        echo "[+] РЕЗУЛЬТАТ: УСПЕХ! HTTP $HTTP_CODE | Скорость: ${SPEED_KBPS} Кбит/с"
    elif [ "$HTTP_CODE" == "200" ]; then
        echo "[!] РЕЗУЛЬТАТ: Частичный успех. Соединение есть (HTTP 200), но скорость задушена: ${SPEED_KBPS} Кбит/с"
    else
        echo "[-] РЕЗУЛЬТАТ: БЛОКИРОВКА или ОБРЫВ. HTTP код: $HTTP_CODE (Скорость: ${SPEED_KBPS} Кбит/с)"
    fi
done

echo "========================================"
echo "=== ТЕСТИРОВАНИЕ СТРАТЕГИЙ ЗАВЕРШЕНО ==="
