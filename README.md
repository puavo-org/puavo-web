
# puavo-web & puavo-rest

Web interface and RESTful API server on top of OpenLDAP with [Puavo
schemas](https://github.com/puavo-org/puavo-ds)

## Hacking


Apply Ansible rules from [puavo-standalone](https://github.com/puavo-org/puavo-standalone).


Clone this repository and install build dependencies

    sudo make install-build-deps

### puavo-web

Install required rubygems and build assets

    make

Stop the puavo-standalone installed puavo-web server and start a development
server

    sudo stop puavo-web
    make server

Access ActiveLdap console

    bundle exec rails runner script/puavo-web-prompt.rb

### puavo-rest

    cd rest

Install required rubygems

    make

Stop the puavo-standalone installed puavo-rest server and start a development
server

    sudo stop puavo-rest
    make server

or with a reloading server

    bundle exec shotgun -o 0.0.0.0 -p 9292

Access model console

    bundle exec scripts/puavo-rest-prompt.rb

