#!/bin/bash
set -eu pipefail

# I've split the first-run checks in multiple places because it takes a lot of time
# to copy from /app/code/frappe-bench/<dir>-orig to /app/data/frappe/<dir> and then
# chown recursively. During development we can delete the .docker/app/data/mysql folder
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
  echo "firstrun: setup /run/logs/frappe"

  mkdir -p /run/logs/frappe
  cp -R /app/code/frappe-bench/logs-orig/* /run/logs/frappe/
  chown -R cloudron:cloudron /run/logs/frappe

  touch /app/data/.log-setup-complete
  echo "Done frappe logs setup"
fi

# Check if db setup is complete (takes no time)
if [[ ! -f /app/data/mysql/.initialized ]]; then

  echo "firstrun: setup /app/data/mysql"

  mkdir -p /app/data/mysql
  cp -R /var/lib/mysql-orig/* /app/data/mysql/
  chown -R mysql:mysql /app/data/mysql

  echo "Done mysql data setup"

  echo "setup /run/logs/mysql"

  mkdir -p /run/logs/mysql
  cp -R /var/log/mysql-orig/* /run/logs/mysql/
  chown -R mysql:mysql /run/logs/mysql

  echo "Done mysql logs setup"

  touch /app/data/mysql/.initialized
fi

echo "Running mysqld_safe..."
mkdir -p /app/data/tmp && chown mysql:mysql /app/data/tmp

# NOTE: --character-set-server and --collation-server options don't work in config file. *SIGH*
mysqld_safe \
  --skip-syslog \
  --character-set-server=utf8mb4 \
  --collation-server=utf8mb4_unicode_ci &

# Wait until mysql process is listening, then wait one more seconds
tail -f /app/data/mysql/*.err | sed '/ready for connections/ q'
sleep 1

echo "mysqld listening..."

tail -f /dev/null

echo "Container is now running; "
echo "now you can enter into this container and run the following commands manually"

# create a new site called cloudron.local
/usr/local/bin/gosu cloudron:cloudron bench new-site \
  --verbose \
  --force \
  --db-name "cloudron" \
  --db-password "cloudron" \
  --db-root-username "root" \
  --db-root-password "root" \
  --admin-password "changeme" cloudron.local

/usr/local/bin/gosu cloudron:cloudron bench use cloudron.local

/usr/local/bin/gosu cloudron:cloudron bench install-app erpnext
