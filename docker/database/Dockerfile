# syntax=docker/dockerfile:1.7

ARG POSTGRES_IMAGE=postgres:18.4-trixie
FROM ${POSTGRES_IMAGE}

COPY docker/database/backup-entrypoint /usr/local/bin/backup-entrypoint

RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends util-linux; \
    rm -rf /var/lib/apt/lists/*; \
    rm -f /usr/local/bin/gosu; \
    chmod 0755 /usr/local/bin/backup-entrypoint; \
    install -d -o postgres -g postgres -m 0700 /backups; \
    command -v setpriv >/dev/null; \
    test ! -e /usr/local/bin/gosu

WORKDIR /backups

ENTRYPOINT ["backup-entrypoint"]
CMD ["backup-loop"]
