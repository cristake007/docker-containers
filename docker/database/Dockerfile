# syntax=docker/dockerfile:1.7

ARG POSTGRES_IMAGE=postgres:18.4-trixie
FROM ${POSTGRES_IMAGE}

COPY docker/database/backup-entrypoint /usr/local/bin/backup-entrypoint

RUN chmod 0755 /usr/local/bin/backup-entrypoint \
    && install -d -o postgres -g postgres -m 0700 /backups

USER postgres
WORKDIR /backups

ENTRYPOINT ["backup-entrypoint"]
CMD ["backup-loop"]
