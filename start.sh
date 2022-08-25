#!/bin/bash
set -eu pipefail

# I've split the first-run checks in multiple places because it takes a lot of time
# to copy from /app/code/frappe-bench/<dir>-orig to /app/data/frappe/<dir> and then
# chown recursively. During development we can delete the .docker/app/data/mariadb folder
# without waiting for .docker/app/data/frapee folder to perform "first-run" again.

# check for frappe framework files
# copy frappe and erpnext, then chown to cloudron (takes a while)
if [[ ! -f /app/data/frappe/.initialized ]]; then
  echo ">>>>  firstrun:  setup /app/data/{config,sites,apps,logs}"
  mkdir -p /app/data/frappe/{config,sites,apps,logs}
  cp -R /app/code/frappe-bench/config-orig/* /app/data/frappe/config/
  cp -R /app/code/frappe-bench/sites-orig/* /app/data/frappe/sites/
  cp -R /app/code/frappe-bench/apps-orig/* /app/data/frappe/apps/
  cp -R /app/code/frappe-bench/logs-orig/* /app/data/frappe/logs/

  chown -R cloudron:cloudron /app/data/frappe

  touch /app/data/frappe/.initialized
  echo ">>>>  Done frappe setup"
fi

# Check for log folders (takes no time)
if [[ ! -f /app/data/.log-setup-complete ]]; then
  echo ">>>>  firstrun: setup /run/frappe/logs"

  mkdir -p /run/frappe/logs
  cp -R /app/code/frappe-bench/logs-orig/* /run/frappe/logs/
  chown -R cloudron:cloudron /run/frappe/logs

  touch /app/data/.log-setup-complete
  echo ">>>>  Done frappe logs setup"
fi

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
  cp -R /var/log/mysql-orig/* /run/mysqld/logs
fi
chown -R mysql:mysql /run/mysqld/logs
echo ">>>>  Done setup /run/mysqld/logs"

if [[ ! -f /app/data/redis/.initialized ]]; then
  echo ">>>>  firstrun: setup /app/data/redis"
  mkdir -p /app/data/redis
  cp -R /etc/redis-orig/* /app/data/redis/
fi
chown -R redis:redis /app/data/redis
echo ">>>>  Done redis data setup"

############# <run mariadb> ##################
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

############# </mariadb> ##################

############# <nginx> ##################
echo ">>>>  Setup directories for nginx"
if [[ ! -d /run/nginx/logs ]]; then
  mkdir -p /run/nginx/logs
fi
chown -R cloudron:cloudron /run/nginx
echo ">>>>  Done nginx dir setup"
############# </nginx> ##################

############# <supervisor> ##################
echo ">>>>  setup /run/supervisor/logs"
if [[ ! -d /run/supervisor/logs ]]; then
  mkdir -p /run/supervisor/logs
fi
chown -R cloudron:cloudron /run/supervisor
echo ">>>>  done /run/supervisor/logs"
############# </supervisor> ##################

############# <default-site> ##################
DEFAULT_SITE=${CLOUDRON_APP_DOMAIN:-'cloudron.local'}
if [[ ! -f "/app/data/frappe/sites/${DEFAULT_SITE}/.initialized" ]]; then
  echo ">>>>  Creating default site with hostname: ${DEFAULT_SITE}"

  echo 'frappe
        erpnext
        payments
        hrms' >/app/data/frappe/sites/apps.txt

  cd /app/code/frappe-bench

  SITE_PWD=$(openssl rand -hex 32)

  /usr/local/bin/gosu cloudron:cloudron bench new-site \
    --verbose \
    --force \
    --db-name "cloudron" \
    --db-password "cloudron" \
    --db-root-username "root" \
    --db-root-password "root" \
    --admin-password "${SITE_PWD}" "${DEFAULT_SITE}"

  echo "Username: Administrator / Password: $SITE_PWD" >"/app/data/${DEFAULT_SITE}-credential.txt"

  /usr/local/bin/gosu cloudron:cloudron bench use "${DEFAULT_SITE}"

  echo ">>>>  enable scheduler for ${DEFAULT_SITE}..."
  /usr/local/bin/gosu cloudron:cloudron bench scheduler enable

  echo ">>>>  installing the payments module..."
  /usr/local/bin/gosu cloudron:cloudron bench install-app payments
  echo ">>>>  done"

  echo ">>>>  installing erpnext..."
  /usr/local/bin/gosu cloudron:cloudron bench install-app erpnext
  echo ">>>>  done"

  touch "/app/data/frappe/sites/${DEFAULT_SITE}/.initialized"
else
  echo ">>>>  Site ${DEFAULT_SITE} already setup."
fi

############# </default-site> ##################
echo ">>>>  Setting up nginx, redis and supervisor..."
# "--logging none" only works "--logging combined" didn't work.
# Without this flag, "main" will be added to access_log, Causing nginx fail to start.
# --yes bypasses prompt
/usr/local/bin/gosu cloudron:cloudron bench setup nginx --yes --logging none
# fix "Conflicting scheme in header" error.
sed -i 's|proxy_set_header X-Forwarded-Proto $scheme;|proxy_set_header X-Forwarded-Proto https; # patched for cloudron|g' /app/data/frappe/config/nginx.conf

/usr/local/bin/gosu cloudron:cloudron bench setup redis

/usr/local/bin/gosu cloudron:cloudron bench setup supervisor --yes
echo ">>>>  Done"

if [[ ! -f "/app/data/frappe/sites/${DEFAULT_SITE}/.hrms_installed" ]]; then

  echo ">>>>  Installing HRMS app (in background) to hostname: ${DEFAULT_SITE}"

  # Install HRMS app; requires Redis to be running, so we do "bench install-app hrms &" to run it as a background job.
  # Right after this, supervisor process will start all the required processes (redis, etc) that this command needs.

  /usr/local/bin/gosu cloudron:cloudron bench install-app hrms &
  echo ">>>>  done"

  touch "/app/data/frappe/sites/${DEFAULT_SITE}/.hrms_installed"

else
  echo ">>>>  HRMS already setup in ${DEFAULT_SITE}"
fi

echo ">>>>  All done. Starting nginx & supervisord..."
echo ">>>> To setup LDAP, open the web terminal and run /app/code/setup-ldap.sh"

echo '[program:nginx]
command=/usr/sbin/nginx -c /etc/nginx/nginx.conf -g "daemon off;"
autostart=true
autorestart=true
priority=10' >/app/data/frappe/config/supervisor-app-nginx.conf

/usr/local/bin/gosu cloudron:cloudron /usr/bin/supervisord --configuration /etc/supervisor/supervisord.conf --nodaemon
