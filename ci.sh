#!/bin/sh

set -x
set -eu

debbox_url="$1"
version="$(cat VERSION)"

sudo apt-get update

sudo apt-get install -y --force-yes puavo-standalone ruby1.9.1 ruby1.9.1-dev libxml2-dev libxslt-dev libsqlite3-dev libmagickwand-dev ldap-utils libpq-dev libssl-dev build-essential libopenssl-ruby xpdf-utils git libreadline6-dev libxml2-dev libxslt1-dev libpq-dev libmagickwand-dev libsqlite3-dev ruby-bundler puavo-client nodejs-bundle puavo-ca-rails redis-server aptirepo-upload puavo-devscripts

# fluentd does not work on standalone installations yet because it's not a
# puavo managed installation. It also might cause log forwarding loops.
sudo stop fluentd || true

sudo puavo-init-standalone --unsafe-passwords opinsys.net

sudo puavo-add-new-organisation --yes hogwarts --username albus --password albus --given-name Albus --surname Dumbledore
sudo puavo-add-new-organisation --yes example --username cucumber --password cucumber --given-name cucumber --surname cucumber
sudo puavo-add-new-organisation --yes anotherorg --username admin --password admin --given-name Admin --surname Administrator

puavo-build-debian-dir
puavo-dch $version
sudo puavo-install-deps debian/control
puavo-debuild

sudo script/test-install.sh

aptirepo-upload -r $APTIREPO_REMOTE -b "git-$(echo "$GIT_BRANCH" | cut -d / -f 2)" ../puavo*.changes
