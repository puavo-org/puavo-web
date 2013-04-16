# puavo-users - standalone

Setup Puavo development environment to a single machine. See also https://github.com/opinsys/puavo-standalone/blob/master/README.md

Install Ruby and other dependencies

12.04 LTS (Precise Pangolin):

    sudo apt-get install ruby1.9.1 ruby1.9.1-dev

    sudo apt-get install libxml2-dev libxslt-dev \
      libsqlite3-dev libmagickwand-dev ldap-utils libpq-dev \
      libssl-dev build-essential libopenssl-ruby xpdf-utils \
      git libreadline6-dev
     
Ubuntu has no bundler for 1.9 ruby. Install it from gem

    sudo gem1.9.1 install bundler

or from our repository

    sudo apt-get install ruby-bundler
    
Install [puavo-client](https://github.com/opinsys/puavo-client) manually or from our repo

    sudo apt-get install puavo-client

Get the sources:

    git clone git://github.com/opinsys/puavo-users.git
    cd puavo-users

Use bundler to install all the required gems
    
    bundle install --deployment

Configure

    bundle exec rake puavo:configuration

Create sessions table to database

    bundle exec rake db:migrate

Start development server

    bundle exec rails server
    
## Production PostgreSQL for sessions

    sudo apt-get install postgresql-9.1
    RAILS_ENV=production bundle exec rake db:migrate

## Test environment

Configure master user (uid=admin,o=puavo) password to the config/ldap.yml file. You can see it from the /etc/puavo/ldap/password file.

Get password

    sudo cat /etc/puavo/ldap/password
    dw9e8t5isdjfaosdf

Set password to the ldap.yml

    test:
      host: <%= PUAVO_ETC.ldap_master %>
      bind_dn: uid=admin,o=puavo
      password: dw9e8t5isdjfaosdf
      base: o=puavo
      method: tls
    
    cucumber:
      host: <%= PUAVO_ETC.ldap_master %>
      bind_dn: uid=admin,o=puavo
      password: dw9e8t5isdjfaosdf
      base: o=puavo
      method: tls

Add test organisation. Owner's username and password must be the *cucumber* 

    puavo-add-new-organisation example --username cucumber --password cucumber --given-name cucumber --surname cucumber

Create sessions table to database

    RAILS_ENV=test bundle exec rake db:migrate

Run tests

    bundle exec cucumber
