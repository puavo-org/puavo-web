require "socket"
require "yaml"
require "puavo/etc"

module PuavoRest

fqdn = Socket.gethostbyname(Socket.gethostname).first

default_config = {
  "ldap" => fqdn,
  "topdomain" => PUAVO_ETC.get(:topdomain),
  "ltsp_server_data_dir" => "/run/puavo-rest",
  "fqdn" => fqdn,
  "keytab" => "/etc/puavo/puavo-rest.keytab",
  "default_organisation_domain" => PUAVO_ETC.get(:domain),
  "bootserver" => true,
  "server" => {
    :dn => PUAVO_ETC.ldap_dn,
    :password => PUAVO_ETC.ldap_password
  },
  "sso" => {
    "localhost" => "secret"
  }
}

if ENV["RACK_ENV"] == "test"
  CONFIG = {
    "ldap" => fqdn,
    "topdomain" => PUAVO_ETC.get(:topdomain),
    "ltsp_server_data_dir" => "/tmp/puavo-rest-test",
    "default_organisation_domain" => "example.opinsys.net",
    "bootserver" => true,
    "server" => {
      :dn => PUAVO_ETC.ldap_dn,
      :password => PUAVO_ETC.ldap_password
    },
    "sso" => {
      "test-client-service.example.com" => "this is a shared secret"
    }
  }
else
  begin
    custom_config = YAML.load_file "/etc/puavo-rest.yml"
  rescue Errno::ENOENT
    custom_config = {}
  end
  CONFIG = default_config.merge(custom_config)
end
end
