#!/bin/sh

set -x
set -eu

sudo apt-get update

# Install build dependencies
sudo make install-build-dep

# Disable minitest expectations. Breaks build on CI for some reason.
# See: https://github.com/seattlerb/minitest/issues/521
export MT_NO_EXPECTATIONS=1

# Build debian package
make deb

mkdir -p $HOME/results
cp ../puavo-*_* $HOME/results
