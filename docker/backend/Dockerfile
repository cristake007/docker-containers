# syntax=docker/dockerfile:1.7

FROM php:8.5-apache-bookworm AS base

ENV COMPOSER_ALLOW_SUPERUSER=1 \
    COMPOSER_HOME=/tmp/composer \
    APACHE_DOCUMENT_ROOT=/var/www/html/public

WORKDIR /var/www/html

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        git \
        unzip \
        libicu-dev \
        libpq-dev \
        libzip-dev \
    && docker-php-ext-install -j"$(nproc)" \
        intl \
        pdo_pgsql \
        zip \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

COPY --from=composer:2 /usr/bin/composer /usr/local/bin/composer

RUN sed -ri \
        's!/var/www/html!${APACHE_DOCUMENT_ROOT}!g' \
        /etc/apache2/sites-available/*.conf \
        /etc/apache2/apache2.conf \
        /etc/apache2/conf-available/*.conf \
    && a2enmod rewrite headers \
    && printf '%s\n' \
        '<Directory /var/www/html/public>' \
        '    Options FollowSymLinks' \
        '    AllowOverride None' \
        '    Require all granted' \
        '    DirectoryIndex index.php' \
        '    FallbackResource /index.php' \
        '</Directory>' \
        > /etc/apache2/conf-available/symfony.conf \
    && a2enconf symfony

RUN cat > /usr/local/bin/app-entrypoint <<'SH'
#!/bin/sh
set -eu

if [ "${APP_ENV:-prod}" = "dev" ]; then
    if [ ! -f composer.json ]; then
        echo "Creating Symfony 8.1 skeleton..."
        rm -rf /tmp/symfony-skeleton
        composer create-project symfony/skeleton:"8.1.*" /tmp/symfony-skeleton \
            --no-install \
            --no-interaction \
            --prefer-dist
        cp -a /tmp/symfony-skeleton/. /var/www/html/
        rm -rf /tmp/symfony-skeleton
        rm -f /var/www/html/.gitkeep
    fi

    if [ ! -f vendor/autoload.php ] || [ composer.lock -nt vendor/autoload.php ]; then
        composer install \
            --prefer-dist \
            --no-interaction \
            --no-progress
    fi
fi

mkdir -p var/cache var/log
chown -R www-data:www-data var || true

exec "$@"
SH

ENTRYPOINT ["sh", "/usr/local/bin/app-entrypoint"]
CMD ["apache2-foreground"]

FROM base AS dev

ENV APP_ENV=dev \
    APP_DEBUG=1

RUN mv "$PHP_INI_DIR/php.ini-development" "$PHP_INI_DIR/php.ini" \
    && printf '%s\n' \
        'opcache.enable=1' \
        'opcache.validate_timestamps=1' \
        'opcache.revalidate_freq=0' \
        > "$PHP_INI_DIR/conf.d/app-opcache.ini"

FROM base AS prod

ENV APP_ENV=prod \
    APP_DEBUG=0

RUN mv "$PHP_INI_DIR/php.ini-production" "$PHP_INI_DIR/php.ini" \
    && printf '%s\n' \
        'expose_php=0' \
        'opcache.enable=1' \
        'opcache.validate_timestamps=0' \
        'opcache.memory_consumption=192' \
        'opcache.max_accelerated_files=20000' \
        > "$PHP_INI_DIR/conf.d/app-opcache.ini"

COPY backend/ ./

RUN composer install \
        --no-dev \
        --prefer-dist \
        --no-interaction \
        --no-progress \
        --classmap-authoritative \
    && mkdir -p var/cache var/log \
    && chown -R www-data:www-data var
