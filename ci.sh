#!/bin/sh

set -x
set -eu

sudo apt-get update

sudo apt-get install -y puavo-standalone ruby1.9.1 ruby1.9.1-dev libxml2-dev libxslt-dev libsqlite3-dev libmagickwand-dev ldap-utils libpq-dev libssl-dev build-essential libopenssl-ruby xpdf-utils git libreadline6-dev libxml2-dev libxslt1-dev libpq-dev libmagickwand-dev libsqlite3-dev ruby-bundler puavo-client nodejs-bundle puavo-ca-rails redis-server

sudo puavo-init-standalone --unsafe-passwords opinsys.net

sudo puavo-add-new-organisation --yes hogwarts --username albus --password albus --given-name Albus --surname Dumbledore
sudo puavo-add-new-organisation --yes example --username cucumber --password cucumber --given-name cucumber --surname cucumber
sudo puavo-add-new-organisation --yes anotherorg --username admin --password admin --given-name Admin --surname Administrator

make
bundle exec rake puavo:configuration
bundle exec rake db:migrate

cd rest
make dev-install
make test
cd ..

RAILS_ENV=test bundle exec rake db:migrate

bundle exec cucumber --tags @start_test_server
bundle exec cucumber --tags ~@start_test_server

