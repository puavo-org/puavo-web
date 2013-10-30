#!/bin/sh

set -x

dpkg -i ../*deb
set -eu
apt-get install -f -y

cd /var/app/puavo-web
RAILS_ENV=production bundle exec rake db:migrate

# Wait for puavo-web to start. It's sloooooow.
sleep 10

curl -v --fail --noproxy "*"  http://localhost:9292/v3/about
echo "puavo-rest .deb package OK!"

curl -v --fail --noproxy "*"  http://localhost:8081/users/login > /dev/null
echo "puavo-web .deb package OK!"
