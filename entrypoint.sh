#!/bin/bash

echo "waiting for Database ..."
while ! mariadb-admin ping -h"$DB_HOST" -u root -p"$MYSQL_ROOT_PASSWORD" --silent; do
    sleep 1
done
echo "Database is ready"

# Setup Redis Config
bench set-config -g redis_cache redis://redis-cache:6379
bench set-config -g redis_queue redis://redis-queue:6379
bench set-config -g redis_socketio redis://redis-socketio:6379

if [ ! -d "sites/site1.local" ]; then
    echo "creating new site site1.local..."
    bench new-site site1.local \
        --admin-password admin \
        --mariadb-root-password "$MYSQL_ROOT_PASSWORD" \
        --db-host "$DB_HOST" \
        --db-root-username root \
        --force

    echo "installing erpnext..."
    bench --site site1.local install-app erpnext
fi

#set defult site
bench use site1.local
python3 -c "import json; f=open('sites/common_site_config.json', 'r'); data=json.load(f); data['default_site']='site1.local'; f=open('sites/common_site_config.json', 'w'); json.dump(data, f, indent=4)"

#start the bench server
echo "starting bench..."
bench serve --port 8000
