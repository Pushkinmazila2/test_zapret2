FROM alpine:latest

# Устанавливаем только необходимый минимум без сохранения кэша пакетов
RUN apk add --no-cache \
    python3 \
    curl \
    iptables \
    ca-certificates \
    tar \
    gzip

# 1. Скачиваем официальный Linux-бинарник yt-dlp
RUN curl -L https://github.com/yt-dlp/yt-dlp/releases/download/2026.08.19/yt-dlp -o /usr/local/bin/yt-dlp \
    && chmod a+rx /usr/local/bin/yt-dlp

# 2. Скачиваем официальный релиз zapret2 v1.0.5.1 под x86_64
RUN curl -sL https://github.com/bol-van/zapret2/releases/download/v1.0.5.1/zapret2-v1.0.5.1.tar.gz -o /tmp/zapret2.tar.gz \
    && mkdir -p /tmp/zapret2_unpack \
    && tar -xzf /tmp/zapret2.tar.gz -C /tmp/zapret2_unpack --strip-components=1 \
    && cp /tmp/zapret2_unpack/binaries/linux-x86_64/nfqws2 /usr/local/bin/nfqws2 \
    && chmod a+rx /usr/local/bin/nfqws2 \
    && mkdir -p /opt/zapret2/lua \
    && cp /tmp/zapret2_unpack/files/fake/zapret-lib.lua /opt/zapret2/lua/ \
    && cp /tmp/zapret2_unpack/files/fake/zapret-antidpi.lua /opt/zapret2/lua/ \
    && rm -rf /tmp/zapret2.tar.gz /tmp/zapret2_unpack

# 3. Создаем бесправного пользователя для изоляции трафика тестов
RUN adduser -D -u 2000 tester

WORKDIR /app
CMD ["sleep", "infinity"]

# Копируем наш будущий скрипт автотеста в контейнер
COPY zapret_autotest.sh /app/zapret_autotest.sh
RUN chmod +x /app/zapret_autotest.sh

# При запуске контейнер будет просто держать сессию открытой, чтобы мы могли зайти внутрь и запустить тест
CMD ["sleep", "infinity"]
