#!/bin/bash

# Ссылка на тестовое видео (любое стабильное видео без ограничений)
TEST_URL="https://www.youtube.com/watch?v=kJQP7kiw5Fk&list=RDkJQP7kiw5Fk&start_radio=1&pp=ygUKZGVzcGFjaXRvIKAHAQ%3D%3D"
TEST_QUEUE=2
TEST_UID=2000

# Ваша 100% рабочая стратегия
INIT_STRATEGY="--filter-tcp=443 --payload=tls_client_hello --lua-desync=fakeddisorder:pos=midsld:tcp_seq=1000000"

# Вариации вашей стратегии fakeddisorder для поиска максимальной скорости
STRATEGIES="
--filter-tcp=443 --payload=tls_client_hello --lua-desync=fakeddisorder:pos=midsld:tcp_seq=1000000
--filter-tcp=443 --payload=tls_client_hello --lua-desync=fakeddisorder:pos=midsld:tcp_seq=2000000
--filter-tcp=443 --payload=tls_client_hello --lua-desync=fakeddisorder:pos=1:tcp_seq=1000000
--filter-tcp=443 --payload=tls_client_hello --lua-desync=fakeddisorder:pos=midsld:tcp_seq=1000000 --dpi-desync-fooling=badsum
--filter-tcp=443 --payload=tls_client_hello --lua-desync=fakeddisorder:pos=midsld:tcp_seq=1000000 --dpi-desync-fooling=md5sig
--filter-tcp=443 --payload=tls_client_hello --lua-desync=fakeddisorder:pos=host:tcp_seq=1000000 --dpi-desync-fooling=badsum
"

echo "=== СТАРТ СТАБИЛЬНОГО АВТОТЕСТА ZAPRET2 ==="

# 1. Сбрасываем старое и фиксируем ОДНО правило iptables на весь запуск скрипта
iptables -t mangle -F OUTPUT 2>/dev/null
iptables -t mangle -A OUTPUT -p tcp --dport 443 -j NFQUEUE --queue-num $TEST_QUEUE

# Перебор стратегий
IFS="
"
echo "$STRATEGIES" | while read -r STRATEGY; do
    [ -z "$STRATEGY" ] && continue
    
    echo "----------------------------------------"
    echo "[*] АКТИВАЦИЯ СТРАТЕГИИ: $STRATEGY"

    # 2. Запускаем nfqws2. Он тут же подхватывает уже готовую очередь ядра
    nfqws2 --queue-num=$TEST_QUEUE $STRATEGY > /dev/null 2>&1 &
    NFQWS_PID=$!
    
    # Даем Lua-движку Запрета 2 секунды на полную инициализацию
    sleep 2

    echo "[+] Замер скорости скачивания файла (6 сек)..."
    # Скачиваем тестовый файл от Google
    DOWNLOAD_RESULT=$(curl -o /dev/null -s -w "%{http_code},%{speed_download}" --max-time 6 "$TEST_URL")
    
    HTTP_CODE=$(echo "$DOWNLOAD_RESULT" | cut -d',' -f1)
    SPEED_BYTES=$(echo "$DOWNLOAD_RESULT" | cut -d',' -f2)
    
    # 3. Гасим nfqws2, освобождая очередь для следующей стратегии
    kill $NFQWS_PID
    wait $NFQWS_PID 2>/dev/null
    sleep 1

    [ -z "$SPEED_BYTES" ] && SPEED_BYTES=0
    SPEED_KBPS=$((SPEED_BYTES * 8 / 1024))

    # Вывод результатов
    if [ "$HTTP_CODE" = "200" ] && [ "$SPEED_KBPS" -gt 2000 ]; then
        echo "[+] РЕЗУЛЬТАТ: ОТЛИЧНО! HTTP $HTTP_CODE | Скорость: ${SPEED_KBPS} Кбит/с"
    elif [ "$HTTP_CODE" = "200" ]; then
        echo "[!] РЕЗУЛЬТАТ: Пробивает, но скорость низкая: ${SPEED_KBPS} Кбит/с"
    else
        echo "[-] РЕЗУЛЬТАТ: БЛОКИРОВКА / ТАЙМАУТ (Код: $HTTP_CODE)"
    fi
done

# В самом конце полностью убираем за собой правила из ядра
iptables -t mangle -F OUTPUT 2>/dev/null
echo "========================================"
echo "=== ТЕСТИРОВАНИЕ СТРАТЕГИЙ ЗАВЕРШЕНО ==="
