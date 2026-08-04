# syntax=docker/dockerfile:1.7

ARG POSTGRES_IMAGE=postgres:18.4-trixie
FROM ${POSTGRES_IMAGE}

RUN set -eux; \
    command -v setpriv >/dev/null; \
    for script in \
        /usr/local/bin/docker-entrypoint.sh \
        /usr/local/bin/docker-ensure-initdb.sh \
        /usr/local/bin/docker-enforce-initdb.sh; \
    do \
        if [ -f "$script" ]; then \
            sed -ri \
                's#exec gosu postgres #exec setpriv --reuid=postgres --regid=postgres --init-groups #' \
                "$script"; \
        fi; \
    done; \
    ! grep -R 'gosu' \
        /usr/local/bin/docker-entrypoint.sh \
        /usr/local/bin/docker-ensure-initdb.sh \
        /usr/local/bin/docker-enforce-initdb.sh; \
    rm -f \
        /usr/local/bin/gosu \
        /etc/ssl/private/ssl-cert-snakeoil.key \
        /etc/ssl/certs/ssl-cert-snakeoil.pem; \
    test ! -e /usr/local/bin/gosu; \
    test ! -e /etc/ssl/private/ssl-cert-snakeoil.key
