# puavo-users - standalone

Setup Puavo development environment to a single machine. See also https://github.com/opinsys/puavo-standalone/blob/master/README.md

## Install Ruby and other dependencies

12.04 LTS (Precise Pangolin):

    sudo apt-get install ruby1.8 rubygems ruby1.8-dev ruby-bundler

    sudo apt-get install libxml2-dev libxslt-dev \
      libsqlite3-dev libmagickwand-dev ldap-utils libpq-dev \
      libssl-dev build-essential libopenssl-ruby xpdf-utils \
      git libreadline6-dev

## Get the sources

    git clone git://github.com/opinsys/puavo-users.git

## Fetch submodules

    cd puavo-users
    git submodule init
    git submodule update

## Use bundler to install all the required Ruby Gems

    cd puavo-users
    bundle install --deployment

## Configurations

    cd puavo-users
    bundle exec rake puavo:configuration

## Create sessions table to database
    cd puavo-users
    bundle exec rake db:migrate

## Start development server
    bundle exec script/server
