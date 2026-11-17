# MySQL 8.0 companion for the Mautic Railway template.
#
# Bakes every constant as ENV because Railway's `templates create` only
# carries ${{...}} expressions into template defaults — literals would land
# on the deploy form as required fields. The only variables on this service
# are MYSQL_ROOT_PASSWORD and MYSQL_PASSWORD (${{secret(32)}}), which the
# mautic service references as ${{mysql.MYSQL_PASSWORD}}.
#
# Volume handling: the official mysql image starts as root and its entrypoint
# chowns the datadir, which tolerates Railway's root-owned volumes. Unlike
# Postgres, MySQL's entrypoint initialises whenever the mysql system-db dir
# is absent, so a direct mount at /var/lib/mysql works despite the volume's
# lost+found (initdb's non-empty-dir refusal is a Postgres-only gotcha).
#
# Digest pinned from the mysql:8.0 tag (a moving tag); the manifest-list
# digest is the pin. Mautic 7 requires MySQL 8.0+ (or MariaDB 10.6+).

FROM mysql:8.0@sha256:7dcddc01f13bab2f15cde676d44d01f61fc9f99fe7785e86196dfc07d358ae2b

ENV MYSQL_DATABASE=mautic \
    MYSQL_USER=mautic

LABEL org.opencontainers.image.source="https://github.com/INAPP-Mobile/mautic"
