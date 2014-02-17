# puavo-users - standalone

Before continuing here you should have a [Puavo environment](https://github.com/opinsys/puavo-standalone) setup.

Install Puavo devscripts

    apt-get install puavo-devscripts

Clone the source

    git clone https://github.com/opinsys/puavo-users.git

Install development dependencies

    mk-build-deps --install debian.default/control
    
Install Ruby gems, node modules and build assets

    make

Generate default configuration

    bundle exec rake puavo:configuration

Start development server

    bundle exec rails server

Now you should be able to login to `http://localhost:3000` with username `albus` and password `albus`.

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

Add testing organisations.

    puavo-add-new-organisation example --username cucumber --password cucumber --given-name cucumber --surname cucumber
    puavo-add-new-organisation anotherorg --username admin --password admin --given-name Admin --surname Administrator

Create sessions table to database

    RAILS_ENV=test bundle exec rake db:migrate

Run tests

    bundle exec cucumber
