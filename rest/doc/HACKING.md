# Hacking

  1. `make dev-install`
    - kinda ugly hack...
  2. make sure `/etc/puavo/ldap` has working dn and password
    - they are used for resolve usernames to dn attributes
    - and boot server auth
  3. `make test` to test things
  4. before releasing create test dep free Gemfile.lock with
     `make update-production-gemfile.lock`

