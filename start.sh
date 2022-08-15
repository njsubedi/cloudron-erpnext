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
  mkdir -p /app/data/frappe/{config,sites,apps,logs,site-packages}
  cp -R /app/code/frappe-bench/config-orig/* /app/data/frappe/config/
  cp -R /app/code/frappe-bench/sites-orig/* /app/data/frappe/sites/
  cp -R /app/code/frappe-bench/apps-orig/* /app/data/frappe/apps/
  cp -R /app/code/frappe-bench/logs-orig/* /app/data/frappe/logs/
  cp -R /app/code/frappe-bench/env/lib/python3.10/site-packages-orig/* /app/data/frappe/site-packages/

  ### IMPORTANT ###
  # The payments module causes crash, so I'm simply patching the utils.py file to remove the
  # Doctypes that cause the crash. This might show unwanted behaviours on the payments module.
  cd /app/data/frappe/apps/payments &&
    git apply frappe-payments-utils-utils.py.patch &&
    cd /app/code/frappe-bench

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
mysqld_safe \
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
if [[ ! -d /app/data/nginx ]]; then
  mkdir -p /app/data/nginx
fi
chown -R cloudron:cloudron /app/data/nginx

if [[ ! -d /run/nginx/logs ]]; then
  mkdir -p /run/nginx/logs
fi
chown -R cloudron:cloudron /run/nginx/logs
echo ">>>>  Done nginx dir setup"
############# </nginx> ##################

############# <supervisor> ##################
echo ">>>>  setup /run/supervisor"
if [[ ! -d /run/supervisor ]]; then
  mkdir -p /run/supervisor
fi
echo ">>>>  done /run/supervisor"
############# </supervisor> ##################

############# <default-site> ##################
DEFAULT_SITE=${CLOUDRON_APP_ORIGIN:-'cloudron.local'}
if [[ ! -f "/app/data/frappe/sites/${DEFAULT_SITE}/.initialized" ]]; then
  echo ">>>>  Creating default site with hostname: ${DEFAULT_SITE}"

  echo 'frappe
        erpnext
        payments
        hrms' > /app/data/frappe/sites/apps.txt

  /usr/local/bin/gosu cloudron:cloudron bench new-site \
    --verbose \
    --force \
    --db-name "cloudron" \
    --db-password "cloudron" \
    --db-root-username "root" \
    --db-root-password "root" \
    --admin-password "changeme" "${DEFAULT_SITE}"

  /usr/local/bin/gosu cloudron:cloudron bench use "${DEFAULT_SITE}"

  echo ">>>>  enable scheduler for ${DEFAULT_SITE}..."
  /usr/local/bin/gosu cloudron:cloudron bench scheduler enable

  echo ">>>>  installing the payments module..."
  /usr/local/bin/gosu cloudron:cloudron bench install-app payments
  echo ">>>>  done"

  echo ">>>>  installing erpnext..."
  /usr/local/bin/gosu cloudron:cloudron bench install-app erpnext
  echo ">>>>  done"



  echo ">>>> ** The HRMS module causes the database tables to crash. **"
  echo ">>>> ** Please report the issue or try to fix if it fails. **"
  echo ">>>>  installing hrms..."
  sleep 10

  /usr/local/bin/gosu cloudron:cloudron bench install-app hrms
  echo ">>>>  done"

  touch "/app/data/frappe/sites/${DEFAULT_SITE}/.initialized"
else
  echo ">>>>  Site ${DEFAULT_SITE} already setup."
fi

############# </default-site> ##################

/usr/local/bin/gosu cloudron:cloudron bench setup nginx --yes --logging combined
/usr/local/bin/gosu cloudron:cloudron bench setup supervisor --yes

/usr/local/bin/gosu cloudron:cloudron /usr/bin/supervisord --configuration /etc/supervisor/supervisord.conf --nodaemon
