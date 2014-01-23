#!/bin/sh

set -x

echo "hogwarts.opinsys.net" > /etc/puavo/domain


dpkg -i ../*deb
set -eu
apt-get install -f -y --force-yes

cp config/initializers/secret_token.rb.development /etc/puavo-web/secret_token.rb

stop puavo-web || true
stop puavo-rest || true

start puavo-web
start puavo-rest

cd /var/app/puavo-web

# Wait for puavo-web to start. It's sloooooow.
sleep 10

curl -v --fail --noproxy "*"  http://localhost:9292/v3/about
echo "puavo-rest .deb package OK!"

curl -v --fail --noproxy "*"  http://localhost:8081/users/login > /dev/null
echo "puavo-web .deb package OK!"
