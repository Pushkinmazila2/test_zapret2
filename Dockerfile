FROM debian:bookworm-slim

# Устанавливаем зависимости: python3 для yt-dlp, curl/wget для тестов, iptables для ротации трафика
RUN apt-get update && apt-get install -y --no-install-recommends \
    python3 \
    python3-pip \
    curl \
    iptables \
    procps \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Скачиваем последнюю версию yt-dlp напрямую с GitHub
RUN curl -L https://github.com -o /usr/local/bin/yt-dlp \
    && chmod a+rx /usr/local/bin/yt-dlp

# Скачиваем бинарник nfqws (Zapret)
# Примечание: Для полноценного теста скачаем скомпилированный релиз zapret под x86_64
RUN curl -L https://githubusercontent.com -o /usr/local/bin/nfqws \
    && chmod a+rx /usr/local/bin/nfqws

WORKDIR /app

# Копируем наш будущий скрипт автотеста в контейнер
COPY zapret_autotest.sh /app/zapret_autotest.sh
RUN chmod +x /app/zapret_autotest.sh

# При запуске контейнер будет просто держать сессию открытой, чтобы мы могли зайти внутрь и запустить тест
CMD ["sleep", "infinity"]
