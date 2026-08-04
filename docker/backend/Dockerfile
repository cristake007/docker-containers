# syntax=docker/dockerfile:1.7

ARG PHP_VERSION=8.5.9

FROM php:${PHP_VERSION}-apache-bookworm AS base

ENV APACHE_DOCUMENT_ROOT=/var/www/html/public
WORKDIR /var/www/html

RUN set -eux; \
    a2enmod rewrite; \
    sed -ri "s!/var/www/html!${APACHE_DOCUMENT_ROOT}!g" \
        /etc/apache2/sites-available/*.conf \
        /etc/apache2/apache2.conf \
        /etc/apache2/conf-available/*.conf; \
    printf '%s\n' \
        'ServerName localhost' \
        '<Directory /var/www/html/public>' \
        '    Options -Indexes +FollowSymLinks' \
        '    AllowOverride None' \
        '    Require all granted' \
        '    DirectoryIndex index.php' \
        '    FallbackResource /index.php' \
        '</Directory>' \
        > /etc/apache2/conf-available/symfony.conf; \
    a2enconf symfony

CMD ["sh", "-c", "mkdir -p var/cache var/log && chown -R www-data:www-data var && exec apache2-foreground"]

FROM base AS dev

ENV APP_ENV=dev \
    APP_DEBUG=1 \
    COMPOSER_ALLOW_SUPERUSER=1

RUN apt-get update \
    && apt-get install -y --no-install-recommends git unzip \
    && rm -rf /var/lib/apt/lists/*

COPY --from=composer:2.10.2 /usr/bin/composer /usr/local/bin/composer
COPY backend/ .
RUN composer install --prefer-dist --no-interaction --no-progress

RUN mv "$PHP_INI_DIR/php.ini-development" "$PHP_INI_DIR/php.ini"
COPY docker/backend/php/dev.ini $PHP_INI_DIR/conf.d/99-app.ini

FROM base AS build

ENV APP_ENV=prod \
    APP_DEBUG=0 \
    COMPOSER_ALLOW_SUPERUSER=1

RUN apt-get update \
    && apt-get install -y --no-install-recommends unzip \
    && rm -rf /var/lib/apt/lists/*

COPY --from=composer:2.10.2 /usr/bin/composer /usr/local/bin/composer
COPY backend/ .
RUN composer install \
        --no-dev \
        --prefer-dist \
        --no-interaction \
        --no-progress \
        --classmap-authoritative

FROM base AS prod

ENV APP_ENV=prod \
    APP_DEBUG=0

RUN mv "$PHP_INI_DIR/php.ini-production" "$PHP_INI_DIR/php.ini"
COPY docker/backend/php/prod.ini $PHP_INI_DIR/conf.d/99-app.ini
COPY --from=build /var/www/html /var/www/html
