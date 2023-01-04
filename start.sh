#!/bin/bash
set -eu pipefail

echo ">>>>  Creating directories"
mkdir -p /run/nginx /run/supervisor/logs /run/mariadb /run/frappe
chown -R cloudron:cloudron /run/nginx
chown -R cloudron:cloudron /run/supervisor/

if [[ ! -f /run/.yarnrc ]]; then
  touch /run/.yarnrc && chown cloudron:cloudron /run/.yarnrc
fi

cd /app/code/frappe-bench

# I've split the first-run checks in multiple places because it takes a lot of time
# to copy from /app/code/frappe-bench/<dir>-orig to /app/data/frappe/<dir> and then
# chown recursively. During development we can delete the .docker/app/data/mariadb folder
# without waiting for .docker/app/data/frapee folder to perform "first-run" again.

# check for frappe framework files
# copy frappe bench, then chown to cloudron (takes a while)
if [[ ! -f /app/data/frappe/.initialized ]]; then
  echo ">>>>  firstrun:  setup /app/data/{config,sites,apps,logs}"
  mkdir -p /app/data/frappe/{env,config,sites,apps,logs}
  cp -R /app/code/frappe-bench/env-orig/* /app/data/frappe/env/
  cp -R /app/code/frappe-bench/config-orig/* /app/data/frappe/config/
  cp -R /app/code/frappe-bench/sites-orig/* /app/data/frappe/sites/
  cp -R /app/code/frappe-bench/apps-orig/* /app/data/frappe/apps/
  cp -R /app/code/frappe-bench/logs-orig/* /app/data/frappe/logs/

  chown -R cloudron:cloudron /app/data/frappe

  touch /app/data/frappe/.initialized
  echo ">>>>  Done frappe setup"
fi

if [[ ! -f /app/data/frappe/patches.txt ]]; then
  cp /app/code/frappe-bench/patches-orig.txt /app/data/frappe/patches.txt
  chown cloudron:cloudron /app/data/frappe/patches.txt
fi

# Check for log folders (takes no time)
if [[ ! -d /run/frappe/logs ]]; then
  echo ">>>>  firstrun: setup /run/frappe/logs"

  mkdir -p /run/frappe/logs
  cp -R /app/code/frappe-bench/logs-orig/* /run/frappe/logs/
  echo ">>>>  Done frappe logs setup"
fi
chown -R cloudron:cloudron /run/frappe/logs

# Check if db setup is complete (takes no time)
if [[ ! -f /app/data/mariadb/.initialized ]]; then

  echo ">>>>  firstrun: setup /app/data/mariadb"

  mkdir -p /app/data/mariadb
  cp -R /var/lib/mysql-orig/* /app/data/mariadb/
  chown -R mysql:mysql /app/data/mariadb

  touch /app/data/mariadb/.initialized
fi
chown -R mysql:mysql /app/data/mariadb
echo ">>>>  Done /app/data/mariadb setup"

echo ">>>>  Setup /run/mysqld/logs"
if [[ ! -d /run/mysqld/logs ]]; then
  mkdir -p /run/mysqld/logs
## sometimes /var/log/mysql-orig/* doesn't exist, and cp failed; can't find a cause, so skipping on the logs part now.
#  cp -R /var/log/mysql-orig/* /run/mysqld/logs
fi
chown -R mysql:mysql /run/mysqld/logs
echo ">>>>  Done setup /run/mysqld/logs"

## Setup mariadb
echo ">>>>  Running mysqld_safe..."

mkdir -p /app/data/tmp && chown mysql:mysql /app/data/tmp

# NOTE: --character-set-server and --collation-server options don't work in config file. *SIGH*
/usr/local/bin/gosu mysql:mysql mysqld_safe \
  --skip-syslog \
  --character-set-server=utf8mb4 \
  --collation-server=utf8mb4_unicode_ci &

sleep 5

# Wait until mysql process is listening
tail -f /app/data/mariadb/*.err | sed '/ready for connections/ q'

echo ">>>>  Success. Daemon mysqld listening."

if [[ ! -f /app/data/mariadb/.root_password ]]; then
  echo ">>>> Changing password for database root user..."
  DB_ROOT_PWD=$(openssl rand -hex 32)
  echo -n "$DB_ROOT_PWD" >>/app/data/mariadb/.root_password

  mysql -uroot -proot -e "SET PASSWORD FOR 'root'@'localhost' = PASSWORD('${DB_ROOT_PWD}');"
  mysql -uroot -proot -e "FLUSH PRIVILEGES;"
  echo "Done."
fi

## Set common redis configuration.
REDIS_URL="redis://${CLOUDRON_REDIS_HOST}:${CLOUDRON_REDIS_PORT}"
## Using sed because `bench config set-common-config -c redis_cache "redis://$CLOUDRON_REDIS_HOST"` didn't work.
sed -i "s|\"redis_cache\": \".*\"|\"redis_cache\": \"$REDIS_URL\"|" /app/data/frappe/sites/common_site_config.json
sed -i "s|\"redis_queue\": \".*\"|\"redis_queue\": \"$REDIS_URL\"|" /app/data/frappe/sites/common_site_config.json
sed -i "s|\"redis_socketio\": \".*\"|\"redis_socketio\": \"$REDIS_URL\"|" /app/data/frappe/sites/common_site_config.json

############# <default-site> ##################
DEFAULT_SITE=${CLOUDRON_APP_DOMAIN:-'cloudron.local'}

if [[ ! -f "/app/data/frappe/sites/${DEFAULT_SITE}/.initialized" ]]; then

  echo ">>>>  Creating default site with hostname: ${DEFAULT_SITE} ..."

  echo 'frappe' >/app/data/frappe/sites/apps.txt

  echo ">>>> Generating passwords..."
  DB_ROOT_PWD=$(</app/data/mariadb/.root_password)
  DB_NAME=$(echo "${DEFAULT_SITE}" | tr '.' '_')
  DB_PWD=$(openssl rand -hex 32)
  SITE_PWD=$(openssl rand -hex 32)

  echo ">>>> Running bench new-site..."

  # Get and Install ErpNext app by default, as it cannot be installed after the initial setup of frappe website is complete.
  gosu cloudron bench get-app --branch ${ERPNEXT_VERSION} --resolve-deps erpnext

  /usr/local/bin/gosu cloudron:cloudron bench new-site \
    --verbose \
    --force \
    --db-name "${DB_NAME}" \
    --db-password "${DB_PWD}" \
    --db-root-username "root" \
    --db-root-password "${DB_ROOT_PWD}" \
    --admin-password "${SITE_PWD}" "${DEFAULT_SITE}" \
    --install-app erpnext

  echo "Website Username: Administrator / Website Password: ${SITE_PWD}" >"/app/data/${DEFAULT_SITE}-credential.txt"

  echo "Database Username: ${DB_NAME} / Database Password: ${DB_PWD}" >>"/app/data/${DEFAULT_SITE}-credential.txt"

  /usr/local/bin/gosu cloudron:cloudron bench use "${DEFAULT_SITE}"

  echo ">>>>  enable scheduler for ${DEFAULT_SITE}..."
  /usr/local/bin/gosu cloudron:cloudron bench scheduler enable
  ############# <nginx> ##################
  echo ">>>> setting nginx port to 8888 for site ${DEFAULT_SITE}"
  bench set-nginx-port ${DEFAULT_SITE} 8888

  echo ">>>>  bench setup nginx"
  /usr/local/bin/gosu cloudron:cloudron bench setup nginx --yes --logging none

  sed -i 's|proxy_set_header X-Forwarded-Proto $scheme;|proxy_set_header X-Forwarded-Proto https; # patched for cloudron|g' /app/data/frappe/config/nginx.conf
  echo ">>>>  Done nginx setup"
  ############# </nginx> ##################

  ############# <supervisor> ##################
  echo ">>>>  bench setup supervisor"

  /usr/local/bin/gosu cloudron:cloudron bench setup supervisor --skip-redis --yes
  sed -i "s,/app/code/frappe-bench/logs/,/run/frappe/logs/,g" /app/data/frappe/config/supervisor.conf

  echo ">>>>  Done supervisor setup"
  ############# </supervisor> ##################

  touch "/app/data/frappe/sites/${DEFAULT_SITE}/.initialized"
else
  echo ">>>>  Site ${DEFAULT_SITE} already setup."
fi
############# </default-site> ##################

## Starting supervisord
echo ">>>>  All done. Starting nginx & supervisord..."
echo ">>>> To setup LDAP, open the web terminal and run /app/code/setup-ldap.sh"

/usr/local/bin/gosu cloudron:cloudron /usr/bin/supervisord --configuration /etc/supervisor/supervisord.conf --nodaemon -i frappe
