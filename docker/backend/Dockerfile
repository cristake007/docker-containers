# syntax=docker/dockerfile:1.7

ARG PHP_VERSION=8.5.9

FROM mlocati/php-extension-installer:2 AS extension-installer

FROM php:${PHP_VERSION}-fpm-trixie AS base

COPY --from=extension-installer /usr/bin/install-php-extensions /usr/local/bin/
RUN install-php-extensions pdo_pgsql intl

WORKDIR /var/www/html

COPY docker/backend/php/zz-docker.conf /usr/local/etc/php-fpm.d/zz-docker.conf

COPY docker/backend/entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
EXPOSE 9000
# -F: stay in the foreground. Without it php-fpm honors the config file's
# daemonize setting (default yes); under Docker that risks the process
# Compose/runc is tracking as "the container" exiting once php-fpm forks
# to the background, which tears the container down out from under the
# newly forked master/workers.
CMD ["php-fpm", "-F"]

FROM base AS dev

ENV APP_ENV=dev \
    APP_DEBUG=1 \
    COMPOSER_ALLOW_SUPERUSER=1

RUN apt-get update \
    && apt-get install -y --no-install-recommends git unzip \
    && rm -rf /var/lib/apt/lists/*

COPY --from=composer:2.10.2 /usr/bin/composer /usr/local/bin/composer
COPY backend/ ./
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
COPY backend/ ./
RUN composer validate --strict --no-check-publish \
    && composer audit --locked --no-interaction \
    && composer install \
        --no-dev \
        --prefer-dist \
        --no-interaction \
        --no-progress \
        --classmap-authoritative \
    && composer check-platform-reqs \
    && php bin/console cache:clear --env=prod --no-debug \
    && php-fpm -t

FROM base AS prod

ENV APP_ENV=prod \
    APP_DEBUG=0

RUN mv "$PHP_INI_DIR/php.ini-production" "$PHP_INI_DIR/php.ini"
COPY docker/backend/php/prod.ini $PHP_INI_DIR/conf.d/99-app.ini
COPY --from=build --chown=root:root /var/www/html /var/www/html

RUN mkdir -p var/cache var/log config/jwt \
    && chown -R www-data:www-data var config/jwt \
    && php-fpm -t
