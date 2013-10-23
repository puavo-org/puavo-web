#!/bin/sh

set -x
set -eu

debbox_url="$1"
version="$(sed -rne 's/^.*VERSION.*\"([0-9\.]+)\".*$/\1/p' config/version.rb)"

sudo apt-get update

sudo apt-get install -y puavo-standalone ruby1.9.1 ruby1.9.1-dev libxml2-dev libxslt-dev libsqlite3-dev libmagickwand-dev ldap-utils libpq-dev libssl-dev build-essential libopenssl-ruby xpdf-utils git libreadline6-dev libxml2-dev libxslt1-dev libpq-dev libmagickwand-dev libsqlite3-dev ruby-bundler puavo-client nodejs-bundle puavo-ca-rails redis-server puavo-devscripts

sudo puavo-init-standalone --unsafe-passwords opinsys.net

sudo puavo-add-new-organisation --yes hogwarts --username albus --password albus --given-name Albus --surname Dumbledore
sudo puavo-add-new-organisation --yes example --username cucumber --password cucumber --given-name cucumber --surname cucumber
sudo puavo-add-new-organisation --yes anotherorg --username admin --password admin --given-name Admin --surname Administrator

puavo-build-debian-dir
puavo-dch $version
puavo-debuild
puavo-deb-upload "$debbox_url" ../*.deb

