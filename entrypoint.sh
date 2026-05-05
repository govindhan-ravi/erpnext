#!/bin/bash

echo "waiting for Database ..."
while !  mariadb -admin ping -h"$DB_HOST" --silent; do
    sleep 1
done
echo "Database is ready"

if [ ! -d "sites/site1.local" ]; then
    echo "creating new site site1.local..."
    bench new-site site1.local \
        --admin-password admin \
        --mariadb-root-password admin \
        --db-host "$DB_HOST" \
        --force

    echo "installing erpnext..."
    bench --site site1.local install-app erpnext
fi

#set defult site
bench use site1.local

#start the bench server
echo "starting bench..."
bench server --port 8000
