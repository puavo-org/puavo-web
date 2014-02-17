# Puavo Web Interface

This document describes how to setup a develoment environment for the Puavo Web Interface.

Before continuing you should have a [Puavo environment](https://github.com/opinsys/puavo-standalone) setup.

Install Puavo devscripts and redis-server

    apt-get install puavo-devscripts redis-server

Clone the source

    git clone https://github.com/opinsys/puavo-users.git
    cd puavo-users

Install development dependencies

    sudo mk-build-deps --install debian.default/control
    
Install Ruby gems, node modules and build assets

    make

Generate default configuration

    bundle exec rake puavo:configuration

Start development server

    bundle exec rails server

Now you should be able to login to `http://localhost:3000` with username `albus` and password `albus`.

## Running tests


Add testing organisations

    sudo puavo-add-new-organisation example --username cucumber --password cucumber --given-name cucumber --surname cucumber
    sudo puavo-add-new-organisation anotherorg --username admin --password admin --given-name Admin --surname Administrator

and run the tests

    make test
