FROM cloudron/base:4.0.0@sha256:31b195ed0662bdb06a6e8a5ddbedb6f191ce92e8bee04c03fb02dd4e9d0286df

# Create all necessary directories

RUN mkdir -p /app/code /app/data/{frappe-bench,mariadb} \
    && chown -R cloudron:cloudron /app/code /app/data

WORKDIR /app/code/frappe-bench

# Remove unnecessary database and php packages (takes some time)
# install mariadb (10.6 default), python (3.10 default) and required python3 packages
RUN apt-get remove -y --purge mongodb-* postgresql-* *mysql* *mariadb* \
    && sudo rm -rf /etc/mysql /var/lib/mysql \
    && apt-get -y autoremove \
    && apt-get -y autoclean \
    && apt-get -y update \
    && apt-get install -y --reinstall --fix-missing \
    wkhtmltopdf xvfb libfontconfig fonts-cantarell xfonts-75dpi xfonts-base \
    python3-setuptools python3 python3-dev python3-pip python3-venv python3-distutils uwsgi-plugin-python3 \
    libssl-dev\
    mariadb-server mariadb-backup\
    && pip3 install frappe-bench

ARG FRAPPE_VERSION=v14.21.0

RUN chown -R 1000:1000 /app/code

# Initialize frappe-bench, whatever it means.
RUN /usr/local/bin/gosu cloudron:cloudron bench init --verbose \
    --frappe-branch ${FRAPPE_VERSION} \
    --skip-redis-config-generation \
    --ignore-exist \
    --python /usr/bin/python3 \
    /app/code/frappe-bench

# [1]This is a standard procedure for Cloudron to move existing "data" somewhere else,
# and put a symlink to /app/data from the original location; on first run, we copy
# files from <dir>-orig to /app/data/<dir>, which in turn points to the actual files.
# anyone who has packaged an app would know this practice.

# Move the folders that frappe would pollute with writes at runtime.
RUN mkdir -p /app/data/frappe \
    && mv /app/code/frappe-bench/sites /app/code/frappe-bench/sites-orig \
    && ln -sf /app/data/frappe/sites /app/code/frappe-bench/sites \
    \
    && mv /app/code/frappe-bench/env /app/code/frappe-bench/env-orig \
    && ln -sf /app/data/frappe/env /app/code/frappe-bench/env \
    \
    && mv /app/code/frappe-bench/config /app/code/frappe-bench/config-orig \
    && ln -sf /app/data/frappe/config /app/code/frappe-bench/config \
    \
    && mv /app/code/frappe-bench/apps /app/code/frappe-bench/apps-orig \
    && ln -sf /app/data/frappe/apps /app/code/frappe-bench/apps \
    \
    && mv /app/code/frappe-bench/logs /app/code/frappe-bench/logs-orig \
    && ln -sf /run/frappe/logs /app/code/frappe-bench/logs \
    \
    && mv /app/code/frappe-bench/patches.txt /app/code/frappe-bench/patches-orig.txt \
    && ln -sf /app/data/frappe/patches.txt /app/code/frappe-bench/patches.txt


# Add our custom mysql/mariadb configuration and run commands Equivalent of mysql_sercure_installation
ADD mysql_custom.cnf /etc/mysql/conf.d/

# If there's a better way to kill the mysqld process, replace `mysqladmin -uroot -proot shutdown`.
# Note: a single sign & below is to send mysqld_safe command to background. Do not change it to double &&.
RUN sudo mysqld_safe & \
    sleep 10 \
    && mysql -uroot -v -e "DELETE FROM mysql.user WHERE user=''" \
    && mysql -uroot -v -e "DELETE FROM mysql.user WHERE user='root' AND host NOT IN ('localhost', '127.0.0.1', '::1')" \
    && mysql -uroot -v -e "DROP DATABASE IF EXISTS test" \
    && mysql -uroot -v -e "DELETE FROM mysql.db WHERE db='test' OR db='test\\_%'" \
    && mysql -uroot -v -e "SET PASSWORD FOR 'root'@'localhost' = PASSWORD('root');" \
    && mysql -uroot -v -e "FLUSH PRIVILEGES;" \
    && mysqladmin -uroot -proot shutdown \
    && mkdir -p /app/data/mariadb \
    && mkdir -p /run/mysqld/logs \
    && mv /var/lib/mysql /var/lib/mysql-orig \
    && mv /var/log/mysql /var/log/mysql-orig \
    && ln -sf /app/data/mariadb /var/lib/mysql \
    && ln -sf /run/mysqld/logs /var/log/mysql

COPY supervisor/ /etc/supervisor/

RUN mkdir -p /run/supervisor/{logs} \
    && sudo ln -s /run/supervisor/logs/supervisord.log /var/log/supervisor/supervisord.log \
    \
    && rm /etc/nginx/sites-enabled/* \
    && ln -sf /run/nginx/access.log /var/log/nginx/access.log \
    && ln -sf /run/nginx/error.log /var/log/nginx/error.log \
    && ln -s /app/data/frappe/config/nginx.conf /etc/nginx/sites-enabled/frappe

RUN ln -sf /run/.yarnrc /home/cloudron/.yarnrc

COPY nginx.conf setup-ldap.sh start.sh /app/pkg/

ENV ERPNEXT_VERSION=v14.11.1

CMD [ "/app/pkg/start.sh" ]