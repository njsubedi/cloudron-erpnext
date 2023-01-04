#!/bin/bash
set -eu pipefail

echo ">>>>  Ensure runtime directories"
mkdir -p /run/nginx && chown -R cloudron:cloudron /run/nginx/
mkdir -p /run/supervisor/logs && chown -R cloudron:cloudron /run/supervisor/
mkdir -p /app/data/frappe/{env,config,sites,apps,logs}
mkdir -p /run/frappe/logs
mkdir -p /app/data/mariadb
mkdir -p /run/mysqld/logs

# Yarn

echo ">>>>  Ensure yarn can run properly"
touch /run/.yarnrc && chown cloudron:cloudron /run/.yarnrc

# Frappe Bench

echo ">>>>  Ensure frappe-bench directory is initialized."
if [[ ! -f /app/data/frappe/.initialized ]]; then
  cp -R /app/pkg/frappe-bench-orig/env/* /app/data/frappe/env/
  cp -R /app/pkg/frappe-bench-orig/config/* /app/data/frappe/config/
  cp -R /app/pkg/frappe-bench-orig/sites/* /app/data/frappe/sites/
  cp -R /app/pkg/frappe-bench-orig/apps/* /app/data/frappe/apps/
  cp -n /app/pkg/frappe-bench-orig/patches.txt /app/data/frappe/patches.txt
  cp -R /app/pkg/frappe-bench-orig/logs/* /run/frappe/logs/
  touch /app/data/frappe/.initialized
fi
chown -R cloudron:cloudron /app/data/frappe
chown -R cloudron:cloudron /run/frappe/logs

# Mariadb

echo ">>>>  Ensure mariadb is initialized."
if [[ ! -f /app/data/mariadb/.initialized ]]; then
  cp -R /var/lib/mysql-orig/* /app/data/mariadb/
  touch /app/data/mariadb/.initialized
fi
chown -R mysql:mysql /app/data/mariadb
chown -R mysql:mysql /run/mysqld/logs

# Mariadb hardening

echo ">>>>  Ensuring default root password for mariadb is changed."

gosu mysql:mysql mysqld_safe --skip-syslog --character-set-server=utf8mb4 --collation-server=utf8mb4_unicode_ci &
sleep 5
# Wait until mysql process is listening...
tail -f /app/data/mariadb/*.err | sed '/ready for connections/ q'

if [[ ! -f /app/data/mariadb/.root_password ]]; then
  DB_ROOT_PWD=$(openssl rand -hex 32)
  echo -n "$DB_ROOT_PWD" >>/app/data/mariadb/.root_password.txt
  echo ">>>>  Changed password for database root user. See mariadb/.root_password.txt file."

  mysql -uroot -proot -e "SET PASSWORD FOR 'root'@'localhost' = PASSWORD('${DB_ROOT_PWD}');"
  mysql -uroot -proot -e "FLUSH PRIVILEGES;"
  echo "Done."

  touch /app/data/mariadb/.root_password
fi

# Redis

gosu cloudron:cloudron bench set-redis-cache-host "${CLOUDRON_REDIS_HOST}:${CLOUDRON_REDIS_PORT}"
gosu cloudron:cloudron bench set-redis-queue-host "${CLOUDRON_REDIS_HOST}:${CLOUDRON_REDIS_PORT}"
gosu cloudron:cloudron bench set-redis-socketio-host "${CLOUDRON_REDIS_HOST}:${CLOUDRON_REDIS_PORT}"

# Default Site

echo ">>>>  Ensuring default site exists"

DEFAULT_SITE=${CLOUDRON_APP_DOMAIN:-'cloudron.local'}
if [[ ! -f "/app/data/frappe/sites/${DEFAULT_SITE}/.initialized" ]]; then

  echo ">>>>  Default site not found. Creating ${DEFAULT_SITE} ..."

  echo ">>>> Generating passwords..."
  DB_ROOT_PWD=$(</app/data/mariadb/.root_password.txt)
  DB_NAME=$(echo "${DEFAULT_SITE}" | tr '.' '_')
  DB_PWD=$(openssl rand -hex 32)
  SITE_PWD=$(openssl rand -hex 32)
  CREDENTIALS_FILE="/app/data/${DEFAULT_SITE}-credential.txt"

  echo ">>>>  Running bench new-site command ..."

  # Make sure frappe is installed by default on this site.
  echo 'frappe' >/app/data/frappe/sites/apps.txt

  # Fetch erpnext app (erpnext is not fetched in docker image to reduce size)
  gosu cloudron bench get-app --branch ${ERPNEXT_VERSION} --resolve-deps erpnext

  gosu cloudron:cloudron bench new-site \
    --force \
    --db-name "${DB_NAME}" \
    --db-password "${DB_PWD}" \
    --db-root-username "root" \
    --db-root-password "${DB_ROOT_PWD}" \
    --admin-password "${SITE_PWD}" "${DEFAULT_SITE}" \
    --install-app erpnext

  # Save Login credentials for future use. User may change it if needed.
  echo -e "Admin Login:    \n Username: Administrator\n Password: ${SITE_PWD} " >"$CREDENTIALS_FILE"
  echo -e "\n\n################\n\nSee ${DEFAULT_SITE}-credential.txt file for username/password.\n\n################\n"

  gosu cloudron:cloudron bench setup add-domain --site "${DEFAULT_SITE}" "${DEFAULT_SITE}"

  touch "/app/data/frappe/sites/${DEFAULT_SITE}/.initialized"
else
  echo ">>>>  Site ${DEFAULT_SITE} already setup."
fi
gosu cloudron:cloudron bench use "${DEFAULT_SITE}"
gosu cloudron:cloudron bench scheduler enable
gosu cloudron:cloudron bench set-config allow_reads_during_maintenance 1
gosu cloudron:cloudron bench set-config nginx_port 8888

# Nginx

echo ">>>>  Setup nginx config."
gosu cloudron:cloudron bench setup nginx --yes --logging none
# Make nginx work with Cloudron reverse proxy.
sed -i 's|proxy_set_header X-Forwarded-Proto $scheme;|proxy_set_header X-Forwarded-Proto https;|g' /app/data/frappe/config/nginx.conf

# Supervisord
echo ">>>>  Setup supervisor config."

gosu cloudron:cloudron bench setup supervisor --skip-redis --yes
# Change log path for all programs to a writable directory
sed -i "s,/app/code/frappe-bench/logs/,/run/frappe/logs/,g" /app/data/frappe/config/supervisor.conf

# Starting supervisord

echo ">>>>  All done. Starting nginx & supervisord..."
gosu cloudron:cloudron /usr/bin/supervisord --configuration /etc/supervisor/supervisord.conf --nodaemon -i frappe
