FROM cloudron/base:3.2.0@sha256:ba1d566164a67c266782545ea9809dc611c4152e27686fd14060332dd88263ea

# Create all necessary directories
# Get rid of the `cmdtest` package that has a command called `yarn`. it conflicts with npm's `yarn` command
# Remove unnecessary database and php packages (takes some time)
# install mariadb-10.3, redis-server and required python3 packages

RUN mkdir -p /app/code /app/data/{frappe-bench,db} /run/{logs} \
    && apt-get remove -y --purge cmdtest mongodb-* postgresql-* *mysql* *mariadb* \
    && sudo rm -rf /etc/mysql /var/lib/mysql \
    && apt-get -y autoremove \
    && apt-get -y autoclean \
    && sed -i 's/archive.ubuntu.com/ubuntu.ntc.net.np/g' /etc/apt/sources.list \
    && add-apt-repository ppa:deadsnakes/ppa \
    && apt-get -y update \
    && apt-get install -y --reinstall --fix-missing \
    mariadb-client-10.3 \
    mariadb-server-10.3 \
    wkhtmltopdf \
    xvfb \
    libfontconfig\
    redis-server\
    python3-setuptools\
    python3.10\
    python3.10-dev\
    python3.10-venv\
    uwsgi-plugin-python3\
    python3-pip\
    python3-venv\
    python3.10-distutils\
    libssl-dev\
    fonts-cantarell\
    xfonts-75dpi\
    xfonts-base

# If we don't install python 3.10, some python functions won't work.
# remove this block to see them.
RUN update-alternatives --install /usr/bin/python3 python3 /usr/bin/python3.10 1 \
    && update-alternatives --install /usr/bin/python3 python3 /usr/bin/python3.8 2 \
    && update-alternatives --set python3 /usr/bin/python3.10

# Not sure if this is required
RUN chown -R 1000:1000 /app/code

# Cannot install python packages as root user
USER cloudron

# pip module throws error in source code without this thing! AGAIN!
RUN curl -sS https://bootstrap.pypa.io/get-pip.py | python3.10

# RUN pip3 install <package> won't work. python code throws errors
RUN python3.10 -m pip install --upgrade wheel \
    && python3.10 -m pip install --upgrade setuptools pip distlib

# This is required because w'er going to install frappe-bench in the ~/.local/bin directory, and running it later
ENV PATH /home/cloudron/.local/bin:$PATH

# frappe-bench will be installed in the ~/.local/.bin directory because of limited permission.
RUN chown -R cloudron:cloudron /app/code/ \
    && python3.10 -m pip install frappe-bench \
    && echo "export PATH=/home/cloudron/.local/bin:\$PATH" >>/home/cloudron/.bashrc \
    && echo "export BENCH_DEVELOPER=0" >>/home/cloudron/.bashrc

# Initialize frappe-bench, whatever it means.
RUN bench init --verbose --ignore-exist --python /usr/bin/python3 /app/code/frappe-bench

# If we run any command outside this directory, it simple FAILS.
WORKDIR /app/code/frappe-bench

# I've already tried pip3 install apps/frappe. It's the same thing; at least we can install specific version
RUN bench get-app payments \
    && bench get-app erpnext

# Required if we later switched to external database; for now we're settling with local mysqld.sock
# RUN jq '.db_host = "127.0.0.1"' /app/code/frappe-bench/sites/common_site_config.json > /tmp/jqtmp \
#    && mv /tmp/jqtmp /app/code/frappe-bench/sites/common_site_config.json

# This will prepare configuration for redis, nginx and supervisor
RUN bench setup redis && bench setup nginx && bench setup supervisor

# Need root access for installing mysql; there could be other ways but it works
USER root

# Basically move config to proper location (see below for details[1])
RUN mkdir -p /run/supervisor && \
    sudo ln -s /app/data/frappe/config/supervisor.conf /etc/supervisor/conf.d/frappe-bench.conf && \
    sudo ln -s /app/data/frappe/config/nginx.conf /etc/nginx/conf.d/frappe-bench.conf && \
    sudo ln -sf /run/supervisor/supervisord.log /var/log/supervisor/supervisord.log

# Add our custom mysql/mariadb configuration
ADD mysql_custom.cnf /etc/mysql/conf.d/

# Equivalent of mysql_sercure_installation
# PS: Root password is essential for Frappe; won't take empty password
# If there's a better way to kill the mysqld process, replace `mysqladmin -uroot -proot shutdown`.
RUN sudo sudo mysqld_safe & \
    sleep 5 \
    && mysql -uroot -v -e "DELETE FROM mysql.user WHERE user=''" \
    && mysql -uroot -v -e "DELETE FROM mysql.user WHERE user='root' AND host NOT IN ('localhost', '127.0.0.1', '::1')" \
    && mysql -uroot -v -e "DROP DATABASE IF EXISTS test" \
    && mysql -uroot -v -e "DELETE FROM mysql.db WHERE db='test' OR db='test\\_%'" \
    && mysql -uroot -v -e "UPDATE mysql.user SET password=PASSWORD('root') WHERE user='root'" \
    && mysql -uroot -proot -v -e "FLUSH PRIVILEGES;" \
    && mysql -uroot -proot -v -e "SET PASSWORD FOR 'root'@'localhost' = PASSWORD(\"root\");" \
    && mysql -uroot -proot -v -e "FLUSH PRIVILEGES;" \
    && mysqladmin -uroot -proot shutdown

# [1]This is a standard procedure for Cloudron to move existing "data" somewhere else, \
# and put a symlink to /app/data from the original location; on first run, we copy
# files from <dir>-orig to /app/data/<dir>, which in turn points to the actual files.
# anyone who has packaged an app would know this practice.
RUN mkdir -p /app/data/mariadb \
    && mkdir -p /run/mysqld/logs \
    && mv /var/lib/mysql /var/lib/mysql-orig \
    && mv /var/log/mysql /var/log/mysql-orig \
    && ln -sf /app/data/mariadb /var/lib/mysql \
    && ln -sf /run/mysqld/logs /var/log/mysql

RUN mkdir -p /app/data/redis /run/redis/logs \
    && mv /etc/redis /etc/redis-orig \
    && ln -sf /app/data/redis /etc/redis

RUN mkdir -p /run/nginx/logs /app/data/nginx \
    && rm -r /var/log/nginx \
    && ln -sf /run/nginx/logs /var/log/nginx \
    && rm -r /var/lib/nginx \
    && ln -sf /app/data/nginx /var/lib/nginx


# Same thing, but for the folders that frappe would pollute with writes
RUN mkdir -p /app/data/frappe \
    && rm -rf /app/code/frappe-bench/apps/erpnext/.git \
    && rm -rf /app/code/frappe-bench/apps/payments/.git \
    && rm -rf /app/code/frappe-bench/apps/frappe/.git \
    && mv /app/code/frappe-bench/sites /app/code/frappe-bench/sites-orig \
    && mv /app/code/frappe-bench/config /app/code/frappe-bench/config-orig \
    && mv /app/code/frappe-bench/apps /app/code/frappe-bench/apps-orig \
    && mv /app/code/frappe-bench/logs /app/code/frappe-bench/logs-orig \
    && ln -sf /app/data/frappe/sites /app/code/frappe-bench/sites \
    && ln -sf /app/data/frappe/config /app/code/frappe-bench/config \
    && ln -sf /app/data/frappe/apps /app/code/frappe-bench/apps \
    && ln -sf /app/data/frappe/logs /app/code/frappe-bench/logs

ADD start.sh /app/code/

CMD [ "/app/code/start.sh" ]