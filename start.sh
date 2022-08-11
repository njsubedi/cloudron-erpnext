#!/bin/bash
set -eu pipefail

# I've split the first-run checks in multiple places because it takes a lot of time
# to copy from /app/code/frappe-bench/<dir>-orig to /app/data/frappe/<dir> and then
# chown recursively. During development we can delete the .docker/app/data/mariadb folder
# without waiting for .docker/app/data/frapee folder to perform "first-run" again.

# check for frappe framework files
# copy frappe and erpnext, then chown to cloudron (takes a while)
if [[ ! -f /app/data/frappe/.initialized ]]; then
  echo "firstrun:  setup /app/data/{config,sites,apps,logs}"
  mkdir -p /app/data/frappe/{config,sites,apps,logs}
  cp -R /app/code/frappe-bench/config-orig/* /app/data/frappe/config/
  cp -R /app/code/frappe-bench/sites-orig/* /app/data/frappe/sites/
  cp -R /app/code/frappe-bench/apps-orig/* /app/data/frappe/apps/
  cp -R /app/code/frappe-bench/logs-orig/* /app/data/frappe/logs/

  chown -R cloudron:cloudron /app/data/frappe

  touch /app/data/frappe/.initialized
  echo "Done frappe setup"
fi

# Check for log folders (takes no time)
if [[ ! -f /app/data/.log-setup-complete ]]; then
  echo "firstrun: setup /run/frappe/logs"

  mkdir -p /run/frappe/logs
  cp -R /app/code/frappe-bench/logs-orig/* /run/frappe/logs/
  chown -R cloudron:cloudron /run/frappe/logs

  touch /app/data/.log-setup-complete
  echo "Done frappe logs setup"
fi

# Check if db setup is complete (takes no time)
if [[ ! -f /app/data/mariadb/.initialized ]]; then

  echo "firstrun: setup /app/data/mariadb"

  mkdir -p /app/data/mariadb
  cp -R /var/lib/mysql-orig/* /app/data/mariadb/
  chown -R mysql:mysql /app/data/mariadb

  touch /app/data/mariadb/.initialized
fi
chown -R mysql:mysql /app/data/mariadb
echo "Done /app/data/mariadb setup"

echo "Setup /run/mysqld/logs"
if [[ ! -d /run/mysqld/logs ]]; then
  mkdir -p /run/mysqld/logs
  cp -R /var/log/mysql-orig/* /run/mysqld/logs
fi
chown -R mysql:mysql /run/mysqld/logs
echo "Done setup /run/mysqld/logs"

if [[ ! -f /app/data/redis/.initialized ]]; then
  echo "firstrun: setup /app/data/redis"
  mkdir -p /app/data/redis
  cp -R /etc/redis-orig/* /app/data/redis/
fi
chown -R redis:redis /app/data/redis
echo "Done redis data setup"

############# <run mariadb> ##################
echo "Running mysqld_safe..."

mkdir -p /app/data/tmp && chown mysql:mysql /app/data/tmp

# NOTE: --character-set-server and --collation-server options don't work in config file. *SIGH*
mysqld_safe \
  --skip-syslog \
  --character-set-server=utf8mb4 \
  --collation-server=utf8mb4_unicode_ci &

sleep 2

# Wait until mysql process is listening
tail -f /app/data/mariadb/*.err | sed '/ready for connections/ q'

echo "Success. Daemon mysqld listening."

############# </mariadb> ##################

############# <nginx> ##################
echo "Setup directories for nginx"
if [[ ! -d /app/data/nginx ]]; then
  mkdir -p /app/data/nginx
fi
chown -R nginx:nginx /app/data/nginx

if [[ ! -d /run/nginx/logs ]]; then
  mkdir -p /run/nginx/logs
fi
chown -R nginx:nginx /run/nginx/logs
echo "Done nginx dir setup"
############# </nginx> ##################

############# <supervisor> ##################
echo "Start supervisor. This will start web server (python) and redis"
if [[ ! -d /run/supervisor ]]; then
  mkdir -p /run/supervisor
fi
############# </supervisor> ##################

/usr/local/bin/gosu cloudron:cloudron /usr/bin/supervisord --configuration /etc/supervisor/supervisord.conf --nodaemon

tail -n 10 -f /run/supervisor/supervisord.log | sed '/success: frappe-bench-redis-cache entered RUNNING state/ q'
tail -n 10 -f /run/supervisor/supervisord.log | sed '/success: frappe-bench-redis-queue entered RUNNING state/ q'
tail -n 10 -f /run/supervisor/supervisord.log | sed '/success: frappe-bench-redis-socketio entered RUNNING state/ q'
tail -n 10 -f /run/supervisor/supervisord.log | sed '/success: frappe-bench-frappe-web entered RUNNING state/ q'
tail -n 10 -f /run/supervisor/supervisord.log | sed '/success: frappe-bench-frappe-schedule entered RUNNING state/ q'
tail -n 10 -f /run/supervisor/supervisord.log | sed '/success: frappe-bench-frappe-default-worker-0  entered RUNNING state/ q'
tail -n 10 -f /run/supervisor/supervisord.log | sed '/success: frappe-bench-frappe-short-worker-0 entered RUNNING state/ q'
tail -n 10 -f /run/supervisor/supervisord.log | sed '/success: frappe-bench-frappe-long-worker-0 entered RUNNING state/ q'

echo "Success. Supervisor processes running."
############# </supervisor> ##################

############# <default-site> ##################
if [[ ! -d /app/data/frappe/sites/cloudron.local ]]; then
  /usr/local/bin/gosu cloudron:cloudron bench new-site \
    --verbose \
    --force \
    --db-name "cloudron" \
    --db-password "cloudron" \
    --db-root-username "root" \
    --db-root-password "root" \
    --admin-password "changeme" cloudron.local

  bench setup nginx
fi
/usr/local/bin/gosu cloudron:cloudron bench use cloudron.local

/usr/local/bin/gosu cloudron:cloudron bench scheduler enable

############# </default-site> ##################

tail -f /dev/null

echo "Container is now running; "
echo "now you can enter into this container and run the following commands manually"

# create a new site called cloudron.local

/usr/local/bin/gosu cloudron:cloudron bench use cloudron.local

/usr/local/bin/gosu cloudron:cloudron bench install-app erpnext
