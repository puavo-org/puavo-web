#!/bin/sh

wait_for_http_ok() {

    for i in $(seq 30); do
        >/dev/null curl -s --max-time 1 --fail --noproxy "*"  "$@" && {
            return 0
        }
        sleep 1
    done

    return 1
}

set -x

# --force-confold keeps the current configuration when the defaults change
dpkg --force-confold -i ../puavo-rest_*.deb ../puavo-web-core_*.deb \
                        ../puavo-web_*.deb
set -eu
apt-get install -f -y --force-yes

service puavo-web stop || true
service puavo-rest stop || true

service puavo-web start
service puavo-rest start

wait_for_http_ok -H "host: hogwarts.puavo.net" http://localhost:9292/v3/ldap_connection_test
echo "puavo-rest .deb package OK!"

wait_for_http_ok http://localhost:8081/users/login
echo "puavo-web .deb package OK!"
