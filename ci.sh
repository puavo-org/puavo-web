#!/bin/sh

set -x
set -eu

sudo apt-get update
sudo apt-get install wget

# Apply puavo-standalone Ansible rules
wget -qO - https://github.com/opinsys/puavo-standalone/raw/master/setup.sh | sudo sh


# Install build dependencies
sudo make install-build-dep

# Build debian package
make deb

sudo script/test-install.sh

aptirepo-upload -r $APTIREPO_REMOTE -b "git-$(echo "$GIT_BRANCH" | cut -d / -f 2)" ../puavo*.changes
