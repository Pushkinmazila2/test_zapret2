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
RUN curl -L https://github.com/yt-dlp/yt-dlp -o /usr/local/bin/yt-dlp \
    && chmod a+rx /usr/local/bin/yt-dlp

# Скачиваем бинарник nfqws (Zapret)
# Примечание: Для полноценного теста скачаем скомпилированный релиз zapret под x86_64
RUN curl -sL https://github.com/bol-van/zapret2/releases/download/v1.0.5.1/zapret2-v1.0.5.1.tar.gz -o /tmp/zapret2.tar.gz \
    && mkdir -p /tmp/zapret2_unpack \
    && tar -xzf /tmp/zapret2.tar.gz -C /tmp/zapret2_unpack --strip-components=1 \
    && cp /tmp/zapret2_unpack/binaries/linux-x86_64/nfqws2 /usr/local/bin/nfqws2 \
    && chmod a+rx /usr/local/bin/nfqws2 \
    && rm -rf /tmp/zapret2.tar.gz /tmp/zapret2_unpack

WORKDIR /app

# Копируем наш будущий скрипт автотеста в контейнер
COPY zapret_autotest.sh /app/zapret_autotest.sh
RUN chmod +x /app/zapret_autotest.sh

# При запуске контейнер будет просто держать сессию открытой, чтобы мы могли зайти внутрь и запустить тест
CMD ["sleep", "infinity"]
