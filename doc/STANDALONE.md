# Puavo Web Interface

This document describes how to setup Puavo Web Interface for development in a standalone [Puavo Environment](https://github.com/opinsys/puavo-standalone).

## Organisation setup

Add organisation.

    sudo puavo-add-new-organisation hogwarts --username albus --password albus --given-name Albus --surname Dumbledore

Create certificates for the new organisation.

    sudo puavo-gen-organisation-certs hogwarts
    
The certificate password is `password` if you used `--unsafe-passwords` with `puavo-init-standalone`.

## Installation from sources

Install Puavo devscripts and redis-server.

    sudo apt-get install puavo-devscripts redis-server

Clone the source.

    git clone https://github.com/opinsys/puavo-users.git
    cd puavo-users

Install development dependencies.

    sudo mk-build-deps --install debian.default/control
    
Install Ruby gems, node modules and build assets.

    make
    
## Configuration

Generate default configuration for hogwarts. This also assumes you used `--unsafe-passwords`.

    bundle exec rake puavo:configuration

## Add testing data

Add some testing data to database so there is some thing to play with.

    bundle exec rails runner db/seeds.rb 

## Running the web server

Start development server.

    bundle exec rails server
    
Start resque worker.

    script/puavo-web-worker

Now you should be able to login to `http://localhost:3000` with username `albus` and password `albus`.

## Running tests


Add testing organisations

    sudo puavo-add-new-organisation example --username cucumber --password cucumber --given-name cucumber --surname cucumber
    sudo puavo-add-new-organisation anotherorg --username admin --password admin --given-name Admin --surname Administrator

and run the tests.

    make test

This will take a while...
    
## Building debian packages

    puavo-build-debian-dir
    puavo-dch $(cat VERSION)
    dpkg-buildpackage -uc -us
