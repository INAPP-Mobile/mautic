#!/bin/bash
# Mautic on Railway.
#
# - Maps Railway's injected PORT onto Apache. The stock image (php:apache
#   base) listens on 80, which Railway never routes to; the entrypoint
#   rewrites Listen + the vhost on every boot. When PORT is unset (a template
#   install sets no PORT variable) it defaults to 8080 — Railway's
#   healthcheck prober targets its default service port.
# - Persists the four upstream dirs on the single Railway volume at /data.
#   The image declares VOLUME for config, var/logs, media/files and
#   media/images, but Railway gives one volume per service, so the
#   entrypoint symlinks each app path into /data (moving any shipped files
#   first). It pre-chowns /data to www-data, so the upstream entrypoint's
#   ownership check passes without its recursive chown.
# - Installs Mautic on first boot via the `mautic:install` CLI (the upstream
#   entrypoint never installs — it only runs migrations when local.php
#   already carries db_driver + site_url). Admin is admin / the generated
#   MAUTIC_ADMIN_PASSWORD, email admin@example.com. The site URL is derived
#   at boot from the live RAILWAY_PUBLIC_DOMAIN (never bake a
#   ${{RAILWAY_PUBLIC_DOMAIN}} template expression — it resolves to a bare
#   https:// on first deploy, before any domain exists); if the install
#   happened before a domain existed, the URL is fixed up on a later boot.
# - Enables the REST API with HTTP Basic auth (api_enabled and
#   api_enable_basic_auth are local.php parameters, both default false;
#   MAUTIC_API_ENABLED as an env var does nothing — Mautic maps only a
#   fixed set of MAUTIC_* env vars in config.php) so contacts/segments can
#   be managed over HTTP Basic auth with the admin credentials.
# - Runs Mautic's own cron jobs in-container (upstream's /templates/
#   mautic_cron: segments + campaigns every 15 min) via the cron daemon,
#   because a one-click deploy has no separate cron service. The worker role
#   is not needed: with no messenger DSN configured, Mautic uses the sync
#   transport and handles messages inline.
# - Delegates to the stock entrypoint (/entrypoint.sh), which re-runs the
#   volume/env/db checks, runs migrations, and starts apache2-foreground.
set -e

PORT="${PORT:-8080}"
: "${MAUTIC_ADMIN_PASSWORD:?MAUTIC_ADMIN_PASSWORD is required (generated template variable)}"
: "${MAUTIC_DB_HOST:?MAUTIC_DB_HOST is required (wired from the mysql companion)}"
: "${MAUTIC_DB_USER:?MAUTIC_DB_USER is required}"
: "${MAUTIC_DB_PASSWORD:?MAUTIC_DB_PASSWORD is required (wired from the mysql companion)}"
: "${MAUTIC_DB_DATABASE:=mautic}"
: "${MAUTIC_DB_PORT:=3306}"

LOCAL_PHP=/var/www/html/config/local.php

# Upstream entrypoint env (docker-entrypoint.sh sets these, but it only runs
# at the very end — step 5 below invokes the upstream check scripts
# directly, so export the same defaults here first. Without them the volume
# and env checks are vacuous (empty MAUTIC_VOLUMES / REQUIRED_MAUTIC_VARIABLES
# lists) and check_local_php_exists writes the template to "/local.php" at
# the container root instead of the app config dir.)
export MAUTIC_VOLUME_CONFIG="${MAUTIC_VOLUME_CONFIG:-/var/www/html/config}"
export MAUTIC_VOLUME_LOGS="${MAUTIC_VOLUME_LOGS:-/var/www/html/var/logs}"
export MAUTIC_VOLUME_MEDIA="${MAUTIC_VOLUME_MEDIA:-/var/www/html/docroot/media}"
export MAUTIC_VOLUME_FILES="${MAUTIC_VOLUME_FILES:-/var/www/html/docroot/media/files}"
export MAUTIC_VOLUME_IMAGES="${MAUTIC_VOLUME_IMAGES:-/var/www/html/docroot/media/images}"
export MAUTIC_VAR="${MAUTIC_VAR:-/var/www/html/var}"
export MAUTIC_CONSOLE="${MAUTIC_CONSOLE:-/var/www/html/bin/console}"
export MAUTIC_WWW_USER="${MAUTIC_WWW_USER:-www-data}"
export MAUTIC_WWW_GROUP="${MAUTIC_WWW_GROUP:-www-data}"
export MAUTIC_VOLUMES="${MAUTIC_VOLUME_CONFIG} ${MAUTIC_VAR} ${MAUTIC_VOLUME_LOGS} ${MAUTIC_VOLUME_MEDIA} ${MAUTIC_VOLUME_FILES} ${MAUTIC_VOLUME_IMAGES}"
export REQUIRED_MAUTIC_VARIABLES="MAUTIC_DB_HOST MAUTIC_DB_USER MAUTIC_DB_PASSWORD DOCKER_MAUTIC_ROLE"

is_installed() {
  php -r "include('${LOCAL_PHP}'); exit(!empty(\$parameters['db_driver']) && !empty(\$parameters['site_url']) ? 0 : 1);"
}

# 1. Apache onto $PORT. The php:apache base ships BOTH mpm_event and
# mpm_prefork enabled; Apache refuses to start (AH00534: more than one MPM
# loaded) until one is disabled. mod_php needs prefork — same fix as the
# FileGator wrapper (upstream ships both MPMs enabled).
sed -i "s/^Listen 80$/Listen ${PORT}/" /etc/apache2/ports.conf
sed -i "s|<VirtualHost \*:80>|<VirtualHost *:${PORT}>|" /etc/apache2/sites-available/000-default.conf
a2dismod mpm_event >/dev/null 2>&1 || true
a2enmod mpm_prefork >/dev/null 2>&1 || true

# 2. The four upstream persistent dirs -> /data (single Railway volume).
mkdir -p /data/config /data/var-logs /data/media-files /data/media-images
link_dir() { # $1 = /data subdir, $2 = app path
  local src="/data/$1" dst="$2"
  mkdir -p "$(dirname "$dst")"
  if [ -L "$dst" ]; then return 0; fi
  if [ -d "$dst" ]; then
    shopt -s dotglob nullglob
    for f in "$dst"/*; do
      local base; base="$(basename "$f")"
      if [ -e "$src/$base" ]; then rm -rf "$f"; else mv "$f" "$src/"; fi
    done
    rmdir "$dst"
  fi
  ln -s "$src" "$dst"
}
link_dir config /var/www/html/config
link_dir var-logs /var/www/html/var/logs
link_dir media-files /var/www/html/docroot/media/files
link_dir media-images /var/www/html/docroot/media/images
chown -R www-data:www-data /data

# 3. Wait for the companion MySQL. The upstream entrypoint only waits 31s;
# first-boot MySQL init can take a minute, so wait up to 5 min here first.
for _ in $(seq 1 150); do
  if mysqladmin --host="${MAUTIC_DB_HOST}" --port="${MAUTIC_DB_PORT}" --user="${MAUTIC_DB_USER}" --password="${MAUTIC_DB_PASSWORD}" ping 2>/dev/null | grep -q "mysqld is alive"; then
    break
  fi
  sleep 2
done

# 4. Site URL, derived at boot from the live public domain.
if [ -n "${RAILWAY_PUBLIC_DOMAIN:-}" ]; then
  SITE_URL="https://${RAILWAY_PUBLIC_DOMAIN}"
else
  SITE_URL="http://localhost"
fi

# 5. Upstream pre-flight checks (idempotent; also creates local.php from the
# template when missing, with db params read from MAUTIC_DB_* env at runtime).
/startup/check_volumes_exist_ownership.sh
/startup/check_environment_variables.sh
/startup/check_database_connection.sh
/startup/check_local_php_exists.sh

# 6. First-boot install via CLI (admin: admin / generated password).
if ! is_installed; then
  echo "[mautic] First boot: installing Mautic at ${SITE_URL} (admin: admin)..."
  su -s /bin/bash www-data -c "php /var/www/html/bin/console mautic:install '${SITE_URL}' --force --admin_username=admin --admin_firstname=Admin --admin_lastname=User --admin_email=admin@example.com --admin_password='${MAUTIC_ADMIN_PASSWORD}' --db_driver=pdo_mysql --db_host='${MAUTIC_DB_HOST}' --db_port='${MAUTIC_DB_PORT}' --db_name='${MAUTIC_DB_DATABASE}' --db_user='${MAUTIC_DB_USER}' --db_password='${MAUTIC_DB_PASSWORD}'"
fi

# 7. Fix up site_url if the install happened before a domain existed, and
# enable the REST API with HTTP Basic auth (local.php parameters, both
# default false).
if is_installed; then
  if [ -n "${RAILWAY_PUBLIC_DOMAIN:-}" ]; then
    CURRENT_URL="$(php -r "include('${LOCAL_PHP}'); echo \$parameters['site_url'] ?? '';")"
    if [ -n "$CURRENT_URL" ] && [ "$CURRENT_URL" != "https://${RAILWAY_PUBLIC_DOMAIN}" ]; then
      echo "[mautic] Updating site_url ${CURRENT_URL} -> https://${RAILWAY_PUBLIC_DOMAIN}"
      sed -i "s#'site_url' => '[^']*'#'site_url' => 'https://${RAILWAY_PUBLIC_DOMAIN}'#" "$LOCAL_PHP"
    fi
  fi
  php -r "
    \$f = '${LOCAL_PHP}';
    include(\$f);
    \$p = \$parameters;
    \$changed = false;
    if (empty(\$p['api_enabled'])) { \$p['api_enabled'] = 1; \$changed = true; }
    if (empty(\$p['api_enable_basic_auth'])) { \$p['api_enable_basic_auth'] = 1; \$changed = true; }
    if (\$changed) {
      file_put_contents(\$f, \"<?php\n\\\$parameters = \".var_export(\$p, true).\";\n\");
      echo \"[mautic] Enabled the REST API with HTTP Basic auth (api_enabled=1, api_enable_basic_auth=1).\n\";
    }
  "
fi

# 8. Mautic's own cron jobs in-container (upstream's crontab: segments and
# campaigns every 15 min). The fifo forwards job output to container stdout.
mkdir -p /opt/mautic/cron
cp -p /templates/mautic_cron /opt/mautic/cron/mautic
crontab -u www-data /opt/mautic/cron/mautic
if [ ! -p /tmp/stdout ]; then rm -f /tmp/stdout; mkfifo /tmp/stdout; chmod 777 /tmp/stdout; fi
declare -p | grep -E 'PHP_INI_VALUE_|MAUTIC' > /tmp/cron.env || true
cron
tail -f /tmp/stdout &

# 9. Stock entrypoint: re-runs the checks, runs migrations, starts Apache.
exec /entrypoint.sh
