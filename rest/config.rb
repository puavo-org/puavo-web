require "socket"
require "yaml"
require "puavo/etc"


fqdn = Socket.gethostbyname(Socket.gethostname).first

default_config = {
  "ldap" => fqdn,
  "ldapmaster" => PUAVO_ETC.get(:ldap_master),
  "topdomain" => PUAVO_ETC.get(:topdomain),
  "fqdn" => fqdn,
  "keytab" => "/etc/puavo/puavo-rest.keytab",
  "default_organisation_domain" => PUAVO_ETC.get(:domain),
  "bootserver" => true,
  "redis" => {
    :db => 0
  },
  "server" => {
    :dn => PUAVO_ETC.ldap_dn,
    :password => PUAVO_ETC.ldap_password
  }
}


if ENV['RACK_ENV'] == 'test' then
  # XXX For testing system we use a strange configuration, where
  # XXX puavo-rest is simultaneously a bootserver and a cloud server.
  # XXX Here, PUAVO_ETC.ldap_dn == "uid=admin,o=puavo" that is not in
  # XXX production anywhere, not in bootservers or in the cloud
  # XXX (bootservers use their own credentials and the cloud server uses
  # XXX "uid=puavo,o=puavo").  This means that, by design, some tests in
  # XXX the test system may return results which do not match what actually
  # XXX happens in production systems, mostly regarding ldap ACLs
  # XXX with the ldap accounts that puavo-rest uses.

  CONFIG = {
    "ldap" => fqdn,
    "ldapmaster" => PUAVO_ETC.get(:ldap_master),
    "topdomain" => "puavo.net",
    "default_organisation_domain" => "example.puavo.net",
    "bootserver" => true,
    "cloud" => true,
    "password_management" => {
      "secret" => "foobar",
      "lifetime" => 600,
      "ip_whitelist" => ['127.0.0.1'],
      "smtp" => {
        "from" => "Puavo Org <no-reply@puavo.net>",
        "via_options" => {
          "address" => "localhost",
          "port" => 25,
          "enable_starttls_auto" => false
        }
      }
    },
    "email_confirm" => {
      "secret" => "barfoo" },
    "redis" => {
      :db => 1
    },
    "server" => {
      :dn => PUAVO_ETC.ldap_dn,
      :password => PUAVO_ETC.ldap_password
    },
    "puavo_ca" => "http://localhost:8080",
  }
else
  customizations = [
    "/etc/puavo-rest.yml",
    "/etc/puavo-rest.d/external_logins.yml",
    "./puavo-rest.yml",
  ].map do |path|
    begin
      YAML.load_file path
    rescue Errno::ENOENT
      {}
    end
  end.reduce({}) do |memo, config|
    memo.merge(config)
  end

  CONFIG = default_config.merge(customizations)

  # If we are running in production mode, but with the intent of running
  # the puavo-web cucumber tests, we merge the external login
  # configurations for testing purposes.  Note that for this to work
  # puavo-rest must be on the same server as puavo-web, because it looks up
  # the configuration file "/etc/puavo-web/organisations.yml".
  if ENV['PUAVO_WEB_CUCUMBER_TESTS'] == 'true' then
    require_relative './lib/external_login_test_config'
    CONFIG.merge!({
      'external_login' =>
        PuavoRest::ExternalLoginTestConfig::get_configuration(),
    })
  end
end

# Load organisations.yml if it exists
begin
  ORGANISATIONS = YAML.load_file('/etc/puavo-web/organisations.yml')
rescue => e
  ORGANISATIONS = {}
end

def get_automatic_email(organisation_name)
  conf = ORGANISATIONS.fetch(organisation_name, {}).fetch('automatic_email_addresses', {})
  return [conf.fetch('enabled', false), conf.fetch('domain', nil)]
end
