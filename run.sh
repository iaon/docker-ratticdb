#!/bin/bash

DATA_PATH=/srv
MYSQL_PATH=${DATA_PATH}/mysql/data
MYSQL_CONFIG=${DATA_PATH}/mysql/.my.cnf
MYSQL_INIT=${DATA_PATH}/mysql/.rattinc_init_db
LOGS_PATH=${DATA_PATH}/logs
RATTIC_PATH=${DATA_PATH}/rattic
RATTIC_STATIC_PATH=${RATTIC_PATH}/static
RATTIC_CONFIG_PATH=${RATTIC_PATH}/conf/local.cfg

if [ ! -d ${DATA_PATH} ]; then
    mkdir -p ${DATA_PATH}
    chmod 755 ${DATA_PATH}
fi

if [ ! -d ${MYSQL_PATH} ]; then
    mkdir -p ${MYSQL_PATH}
    mysql_install_db --basedir=/usr --datadir=${MYSQL_PATH} --plugin-dir=/usr/lib/mysql/plugin > /dev/null
    chown -R mysql:mysql $(dirname ${MYSQL_PATH})
    chmod 700 $(dirname ${MYSQL_PATH})
fi

if [ ! -d ${LOGS_PATH} ]; then
    mkdir -p ${LOGS_PATH}
    chmod 755 ${LOGS_PATH}
fi

if [ ! -f /srv/apache.conf ]; then
    cp /etc/apache2/sites-available/rattic /srv/apache.conf
fi

# Starting supervisord
supervisord -n -c /etc/supervisor/supervisord.conf &

# Ensure Rattic dir exists
if [ ! -d ${RATTIC_PATH} ]; then
    mkdir -p ${RATTIC_PATH}
fi

if [ ! -d ${RATTIC_STATIC_PATH} ]; then
    mkdir -p ${RATTIC_STATIC_PATH}
fi

# Ensure Rattic config
if [ ! -f ${RATTIC_CONFIG_PATH} ]; then
    mkdir -p $(dirname ${RATTIC_CONFIG_PATH})
    cp /opt/rattic/conf/local.dist.cfg ${RATTIC_CONFIG_PATH}
    sed -i "s/%SECRET_KEY%/$(openssl rand -base64 48 | cut -c1-32 | tr '/' '-')/g" ${RATTIC_CONFIG_PATH}
fi

# Ensure rights
chown www-data:www-data $(dirname ${RATTIC_CONFIG_PATH})
chmod 755 $(dirname ${RATTIC_CONFIG_PATH})
chown www-data:www-data ${RATTIC_STATIC_PATH}
chmod 755 ${RATTIC_STATIC_PATH}
chown www-data:www-data ${RATTIC_CONFIG_PATH}
chmod 600 ${RATTIC_CONFIG_PATH}

# Wait for mysql
echo -n "Wait for mysql to be ready:"
while true; do
    if mysqladmin ping 2>/dev/null > /dev/null; then
        echo ""
        break
    fi
    echo -n "."
    sleep 1
done

# Generate root password for mysql
if [ ! -f ${MYSQL_CONFIG} ]; then
    ROOT_PW=$(openssl rand -base64 48 | cut -c1-32 | tr '/' '-')
    echo -e "[client]\nuser=root\npassword=${ROOT_PW}\n" > ${MYSQL_CONFIG}
    mysqladmin password "${ROOT_PW}"
fi

# Create database for ratticdb
if [ ! -f ${MYSQL_INIT} ]; then
    RATTIC_PW=$(openssl rand -base64 48 | cut -c1-32 | tr '/' '-')
    sed -i "s/%MYSQL_PASSWORD%/${RATTIC_PW}/g" ${RATTIC_CONFIG_PATH}
    mysql --defaults-file=${MYSQL_CONFIG} -e "create database rattic; grant all on rattic.* to rattic@localhost identified by '"${RATTIC_PW}"';"
    touch ${MYSQL_INIT}
fi

# Ensure rights
chown root:root ${MYSQL_CONFIG}
chmod 600 ${MYSQL_CONFIG}

# Migrate database config
su -c "cd /opt/rattic/ && ./manage.py syncdb --noinput && ./manage.py migrate --all" www-data
su -c "cd /opt/rattic/ && ./manage.py collectstatic -c --noinput" www-data

# Wait for supervisord
wait
