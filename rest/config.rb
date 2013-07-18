require "socket"
require "yaml"

module PuavoRest

fqdn = Socket.gethostbyname(Socket.gethostname).first

if ENV["RACK_ENV"] == "test"
  CONFIG = {
    "ldap" => fqdn,
    "ltsp_server_data_dir" => "/tmp/puavo-rest-test",
    "default_organisation_domain" => "example.opinsys.net",
    "bootserver" => true,
    "server" => {
      :dn => PUAVO_ETC.ldap_dn,
      :password => PUAVO_ETC.ldap_password
    },
    "remote_auth" => {
      "test-client-service.example.com" => "this is a shared secret"
    }
  }
else
  begin
    CONFIG = YAML.load_file "/etc/puavo-rest.yml"
  rescue Errno::ENOENT
    # Do automatc configuration on boot servers
    require "puavo/etc"
    CONFIG = {
      "ldap" => fqdn,
      "ltsp_server_data_dir" => "/run/puavo-rest",
      "fqdn" => fqdn,
      "keytab" => "/etc/puavo/puavo-rest.keytab",
      "default_organisation_domain" => PUAVO_ETC.domain,
      "bootserver" => true,
      "server" => {
        :dn => PUAVO_ETC.ldap_dn,
        :password => PUAVO_ETC.ldap_password
      },
      "remote_auth" => {
        "foobar" => "this is a shared secret"
      }
    }
  end
end
end
