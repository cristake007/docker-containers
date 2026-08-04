# syntax=docker/dockerfile:1.7

ARG PHP_VERSION=8.5.9

FROM php:${PHP_VERSION}-apache-bookworm AS runtime

ENV APACHE_DOCUMENT_ROOT=/var/www/html/public

WORKDIR /var/www/html

RUN set -eux; \
    savedAptMark="$(apt-mark showmanual)"; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
        libicu-dev \
        libpq-dev \
        libzip-dev \
    ; \
    docker-php-ext-install -j "$(nproc)" \
        intl \
        pdo_pgsql \
        zip \
    ; \
    extensionDir="$(php -r 'echo ini_get("extension_dir");')"; \
    apt-mark auto '.*' > /dev/null; \
    apt-mark manual $savedAptMark; \
    ldd "$extensionDir"/*.so \
        | awk '/=>/ { so = $(NF-1); if (index(so, "/usr/local/") == 1) { next } gsub("^/(usr/)?", "", so); print so }' \
        | sort -u \
        | xargs -r dpkg-query --search \
        | cut -d: -f1 \
        | sort -u \
        | xargs -r apt-mark manual; \
    apt-get purge -y --auto-remove -o APT::AutoRemove::RecommendsImportant=false \
        autoconf \
        dpkg-dev \
        file \
        g++ \
        gcc \
        libc6-dev \
        libicu-dev \
        libpq-dev \
        libzip-dev \
        make \
        pkg-config \
        re2c \
    ; \
    rm -rf /var/lib/apt/lists/*; \
    ! ldd "$extensionDir"/*.so | grep 'not found'

RUN set -eux; \
    sed -ri \
        's!/var/www/html!${APACHE_DOCUMENT_ROOT}!g' \
        /etc/apache2/sites-available/*.conf \
        /etc/apache2/apache2.conf \
        /etc/apache2/conf-available/*.conf; \
    a2enmod rewrite headers; \
    printf '%s\n' \
        'ServerName localhost' \
        'ServerTokens Prod' \
        'ServerSignature Off' \
        'TraceEnable Off' \
        > /etc/apache2/conf-available/zz-container-hardening.conf; \
    printf '%s\n' \
        '<Directory /var/www/html/public>' \
        '    Options -Indexes +FollowSymLinks' \
        '    AllowOverride None' \
        '    Require all granted' \
        '    DirectoryIndex index.php' \
        '    FallbackResource /index.php' \
        '</Directory>' \
        '' \
        'Alias /healthz /usr/local/share/container-healthz.php' \
        '<Directory /usr/local/share>' \
        '    Require all granted' \
        '</Directory>' \
        > /etc/apache2/conf-available/symfony.conf; \
    a2enconf symfony zz-container-hardening; \
    printf '%s\n' \
        '<?php' \
        'declare(strict_types=1);' \
        'header("Content-Type: text/plain; charset=utf-8");' \
        'header("Cache-Control: no-store");' \
        'header("X-Container-Health: php");' \
        'echo "ok\n";' \
        > /usr/local/share/container-healthz.php

RUN cat > /usr/local/bin/container-healthcheck <<'SH'
#!/bin/sh
set -eu

php -r '
    $headers = @get_headers("http://127.0.0.1/healthz", true);
    $body = @file_get_contents("http://127.0.0.1/healthz");
    $marker = is_array($headers) ? ($headers["X-Container-Health"] ?? null) : null;

    if ($body !== "ok\n" || $marker !== "php") {
        exit(1);
    }

    if (getenv("HEALTHCHECK_REQUIRE_READY") !== "1") {
        exit(0);
    }

    $readyHeaders = @get_headers("http://127.0.0.1/readyz", true);
    $readyBody = @file_get_contents("http://127.0.0.1/readyz");
    $readyMarker = is_array($readyHeaders) ? ($readyHeaders["X-Application-Readiness"] ?? null) : null;

    exit($readyBody === "ready\n" && $readyMarker === "database" ? 0 : 1);
'
SH

RUN cat > /usr/local/bin/app-entrypoint <<'SH'
#!/bin/sh
set -eu

for secretPath in "${APP_SECRET_FILE:-}" "${DATABASE_PASSWORD_FILE:-}"; do
    if [ -z "$secretPath" ] || [ ! -r "$secretPath" ] || [ ! -s "$secretPath" ]; then
        echo "Required runtime secret is missing or unreadable." >&2
        exit 1
    fi
done

if [ "${APP_ENV:-prod}" = "dev" ]; then
    if [ ! -f composer.json ]; then
        echo "Initializing Symfony backend from the prepared image..."
        cp -a /opt/app-template/. /var/www/html/
        rm -f /var/www/html/.gitkeep
    elif [ ! -f vendor/autoload.php ]; then
        echo "Restoring development dependencies from the prepared image..."
        rm -rf vendor
        cp -a /opt/app-template/vendor ./vendor
    fi

    if [ -f composer.lock ]; then
        lockHash="$(sha256sum composer.lock | cut -d ' ' -f 1)"
        installedHash="$(cat vendor/.composer-lock.sha256 2>/dev/null || true)"

        if [ "$lockHash" != "$installedHash" ]; then
            echo "Synchronizing development dependencies with composer.lock..."
            composer install \
                --prefer-dist \
                --no-interaction \
                --no-progress
            printf '%s\n' "$lockHash" > vendor/.composer-lock.sha256
        fi
    fi
fi

mkdir -p var/cache var/log
chown -R www-data:www-data var

exec docker-php-entrypoint "$@"
SH

RUN chmod 0755 /usr/local/bin/app-entrypoint /usr/local/bin/container-healthcheck

ENTRYPOINT ["app-entrypoint"]
CMD ["apache2-foreground"]

FROM runtime AS builder

ARG BOOTSTRAP_SYMFONY=0

ENV COMPOSER_ALLOW_SUPERUSER=1 \
    COMPOSER_HOME=/tmp/composer \
    APP_SECRET_FILE=/tmp/build-app-secret \
    DATABASE_HOST=127.0.0.1 \
    DATABASE_PORT=5432 \
    DATABASE_NAME=build \
    DATABASE_USER=build \
    DATABASE_PASSWORD_FILE=/tmp/build-database-password \
    DATABASE_SERVER_VERSION=18 \
    TRUSTED_PROXIES=127.0.0.1 \
    CORS_ALLOW_ORIGINS= \
    CORS_ALLOW_HEADERS=Authorization,Content-Type \
    CORS_ALLOW_CREDENTIALS=0 \
    CORS_MAX_AGE=600

RUN apt-get update \
    && apt-get install -y --no-install-recommends git unzip \
    && rm -rf /var/lib/apt/lists/* \
    && printf '%s' 'build-only-app-secret' > /tmp/build-app-secret \
    && printf '%s' 'build-only-database-password' > /tmp/build-database-password

COPY --from=composer:2.10.2 /usr/bin/composer /usr/local/bin/composer
COPY backend/ /tmp/backend/
COPY docker/backend/app/ /opt/container-app/

RUN set -eux; \
    if [ -f /tmp/backend/composer.json ]; then \
        if [ ! -f /tmp/backend/composer.lock ]; then \
            echo "backend/composer.lock is required; update dependencies in development and commit the lock file." >&2; \
            exit 1; \
        fi; \
        mkdir -p /opt/app; \
        cp -a /tmp/backend/. /opt/app/; \
        cd /opt/app; \
        composer install \
            --prefer-dist \
            --no-interaction \
            --no-progress; \
    elif [ "$BOOTSTRAP_SYMFONY" = "1" ]; then \
        composer create-project symfony/skeleton:"8.1.*" /opt/app \
            --prefer-dist \
            --no-interaction \
            --no-progress; \
        cd /opt/app; \
        composer require \
            symfony/orm-pack \
            doctrine/doctrine-migrations-bundle \
            --prefer-dist \
            --no-interaction \
            --no-progress; \
        cp -a /opt/container-app/. /opt/app/; \
    else \
        echo "Production builds require committed Symfony source and backend/composer.lock." >&2; \
        exit 1; \
    fi; \
    cd /opt/app; \
    composer show --locked doctrine/doctrine-bundle >/dev/null; \
    composer show --locked doctrine/doctrine-migrations-bundle >/dev/null; \
    for requiredFile in \
        config/packages/container.yaml \
        config/packages/doctrine.yaml \
        config/packages/doctrine_migrations.yaml \
        migrations/Version20260804000000.php \
        src/Controller/ReadinessController.php \
        src/EventSubscriber/CorsSubscriber.php; \
    do \
        if [ ! -f "$requiredFile" ]; then \
            echo "Required application integration file is missing: $requiredFile" >&2; \
            exit 1; \
        fi; \
    done; \
    composer validate --no-check-publish; \
    composer check-platform-reqs; \
    composer audit --locked --no-interaction; \
    php bin/console lint:container; \
    php bin/console lint:yaml config; \
    sha256sum composer.lock | cut -d ' ' -f 1 > vendor/.composer-lock.sha256; \
    rm -rf /tmp/backend /opt/container-app var/cache/* var/log/*

FROM builder AS production-builder

RUN set -eux; \
    cp -a /opt/app /opt/app-prod; \
    cd /opt/app-prod; \
    composer install \
        --no-dev \
        --prefer-dist \
        --no-interaction \
        --no-progress \
        --classmap-authoritative; \
    rm -f vendor/.composer-lock.sha256; \
    APP_ENV=prod APP_DEBUG=0 php bin/console cache:clear --no-debug; \
    APP_ENV=prod APP_DEBUG=0 php bin/console cache:warmup --no-debug

FROM builder AS dev

ENV APP_ENV=dev \
    APP_DEBUG=1

RUN mv "$PHP_INI_DIR/php.ini-development" "$PHP_INI_DIR/php.ini"

COPY docker/backend/php/dev.ini $PHP_INI_DIR/conf.d/99-app.ini

RUN cp -a /opt/app /opt/app-template

FROM runtime AS prod

ENV APP_ENV=prod \
    APP_DEBUG=0

RUN mv "$PHP_INI_DIR/php.ini-production" "$PHP_INI_DIR/php.ini"

COPY docker/backend/php/prod.ini $PHP_INI_DIR/conf.d/99-app.ini
COPY --from=production-builder /opt/app-prod /var/www/html

RUN mkdir -p var/cache var/log \
    && chown -R www-data:www-data var
