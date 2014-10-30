
# puavo-web & puavo-rest

Web interface and api server on top of OpenLDAP with [Puavo
schemas](https://github.com/opinsys/puavo-ds)

## Hacking


Apply Ansible rules from [puavo-standalone](https://github.com/opinsys/puavo-standalone).


Clone this repository and install build dependencies

    sudo make install-build-dep

### puavo-web

Install required rubygems and build assets

    make

Stop the puavo-standalone installed puavo-web server and start a development
server

    sudo stop puavo-web
    bundle exec rails server

If you need to hack on the worker process

    sudo stop puavo-web-worker
    bundle exec rake resque:work QUEUE='*' VERBOSE=true

Access ActiveLdap console

    bundle exec rails runner script/puavo-web-prompt.rb

### puavo-rest

    cd rest

Install required rubygems

    make

Stop the puavo-standalone installed puavo-rest server and start a development
server

    sudo stop puavo-web
    bundle exec puma -p 9292

or with a reloading server

    bundle exec shotgun -o 0.0.0.0 -p 9292

Access model console

    bundle exec scripts/puavo-rest-prompt.rb

