#!/bin/sh

wait_for_http_ok() {
    local url=$1

    for i in $(seq 30); do
        >/dev/null curl -s -H "host: hogwarts.opinsys.net" --max-time 1 --fail --noproxy "*"  "$url" && {
            return 0
        }
        sleep 1
    done

    return 1
}

set -x

dpkg -i ../*deb
set -eu
apt-get install -f -y --force-yes

stop puavo-web || true
stop puavo-rest || true

start puavo-web
start puavo-rest

cd /var/app/puavo-web

wait_for_http_ok http://localhost:9292/v3/ldap_connection_test
echo "puavo-rest .deb package OK!"

wait_for_http_ok http://localhost:8081/users/login
echo "puavo-web .deb package OK!"
