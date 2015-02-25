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

mkdir -p $HOME/results
cp ../puavo-*_ $HOME/results
