# MySQL 8.4 companion for the Mautic Railway template.
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
# Digest pinned from the mysql:8.4 tag (a moving tag); the manifest-list
# digest is the pin. Mautic 7 REQUIRES MySQL 8.4.0+ (or MariaDB 10.11.0+) —
# proven in e2e 2026-11-17: mautic:install refuses MySQL 8.0.46 with
# "Your database version (8.0.46) is too old for Mautic to work correctly."
# Do NOT downgrade this to 8.0.

FROM mysql:8.4@sha256:a81d043930e51745522bd5c430961cf8286f0a23f0a9a2a6e0108f7ea71b0902

ENV MYSQL_DATABASE=mautic \
    MYSQL_USER=mautic

LABEL org.opencontainers.image.source="https://github.com/INAPP-Mobile/mautic"
