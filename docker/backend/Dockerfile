# syntax=docker/dockerfile:1.7

ARG PHP_VERSION=8.5.9

# Pinned by digest, not just a mutable tag: the same source commit should
# build the same third-party code later, not silently pull in whatever a
# tag happens to point to by then (see AUDIT_FINDINGS.md F-011). Bumping
# PHP_VERSION or either digest is a deliberate, reviewed change.
FROM mlocati/php-extension-installer:2@sha256:b6d3fa381b9ba5cf051117c1c601d6a523b590e534bf3d56eb4fbe352949c138 AS extension-installer

FROM php:${PHP_VERSION}-fpm-trixie@sha256:227ae08b7b6c5cbec7d4048ed7e45cd608c323d151573f83c0e7ec06c5787b79 AS base

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

# Neither cgi-fcgi nor nc exist in this base image, so this can't speak
# FastCGI or do a plain TCP probe the usual way -- php itself always does,
# so a raw socket connect from a one-line PHP script is what's available.
# This only proves the FastCGI socket is accepting connections, not that
# the application behind it is correct -- that's what the smoke tests are
# for (see tests/).
HEALTHCHECK --interval=10s --timeout=3s --start-period=10s --retries=3 \
    CMD php -r 'exit(@fsockopen("127.0.0.1", 9000, $e, $s, 2) ? 0 : 1);'

FROM base AS dev

ENV APP_ENV=dev \
    APP_DEBUG=1 \
    COMPOSER_ALLOW_SUPERUSER=1

RUN apt-get update \
    && apt-get install -y --no-install-recommends git unzip \
    && rm -rf /var/lib/apt/lists/*

COPY --from=composer:2.10.2@sha256:4d71c3c2109c61d5415544264b59ad4087e4c5b7244481723664138fd36d5040 /usr/bin/composer /usr/local/bin/composer
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

COPY --from=composer:2.10.2@sha256:4d71c3c2109c61d5415544264b59ad4087e4c5b7244481723664138fd36d5040 /usr/bin/composer /usr/local/bin/composer
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
