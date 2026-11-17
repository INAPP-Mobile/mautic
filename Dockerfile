# Mautic 7.2.2 — open-source marketing automation (mautic/mautic, GPL-3.0).
#
# Upstream image pinned by manifest-list digest, WITHOUT a tag: Railpack
# 0.43.0 fails to detect a Dockerfile whose FROM carries both a tag and a
# digest, so redeploys die in the plan phase while the first deploy succeeds.
# The digest-only form builds under both builders. Version lives here in the
# comment: mautic/mautic:7.2.2-apache, manifest list
# sha256:83461b9ec7c109413281490180e1f96c379aa935bd92f80c68294f98487a9015
# (amd64 sha256:84ec7fbf7f47e54692dfd5bc788af1ff0be38ef31ac178a554fc5d743a95fdda).
FROM mautic/mautic@sha256:83461b9ec7c109413281490180e1f96c379aa935bd92f80c68294f98487a9015

# The stock image carries no USER directive (it runs as root) — state it
# explicitly: Railway mounts persistent volumes root-owned, and the upstream
# entrypoint itself chowns the volume dirs to www-data (it runs as root and
# drops to www-data for the app). A non-root wrapper user would break both.
USER root

# Baked defaults. These literals never appear on the one-click deploy form.
# MAUTIC_DB_HOST / MAUTIC_DB_PASSWORD come from the MySQL companion service
# as ${{mysql.RAILWAY_PRIVATE_DOMAIN}} / ${{mysql.MYSQL_PASSWORD}} (see
# companion-mapping.json); MAUTIC_DB_PORT/DATABASE/USER are constants of the
# companion image. The admin PASSWORD is a generated secret — see
# template-vars.json. MAUTIC_API_ENABLED does NOT work as an env var (Mautic
# only maps a fixed set of MAUTIC_* env vars in config.php; api_enabled is a
# local.php parameters) — the entrypoint enables the API + Basic auth by writing them into
# local.php after install instead.
ENV TZ=UTC \
    MAUTIC_DB_PORT=3306 \
    MAUTIC_DB_DATABASE=mautic \
    MAUTIC_DB_USER=mautic

COPY entrypoint.sh /railway-entrypoint.sh
RUN chmod +x /railway-entrypoint.sh

# Config (local.php), logs, and uploaded media all live under /data, mounted
# as a Railway volume (do NOT add a Dockerfile VOLUME instruction — Railway's
# builder rejects it: "docker VOLUME ... is not supported, use Railway
# Volumes"). The entrypoint symlinks the four upstream persistent dirs into
# /data; the stock image's own VOLUME declarations are ignored by Railway's
# runtime, so the symlinks replace plain image dirs.

# The stock image listens on 80 (php:apache base); the entrypoint remaps
# Apache onto Railway's injected PORT on every boot. When PORT is unset (a
# template install sets no PORT variable), it defaults to 8080 — Railway's
# healthcheck prober targets its default service port.
EXPOSE 8080

# No CMD: the entrypoint installs Mautic on first boot (mautic:install CLI),
# starts the upstream cron jobs in-container, then execs the stock
# entrypoint, which runs migrations and starts apache2-foreground.
ENTRYPOINT ["/railway-entrypoint.sh"]

LABEL org.opencontainers.image.source="https://github.com/INAPP-Mobile/mautic"
