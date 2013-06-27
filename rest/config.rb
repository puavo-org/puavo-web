require "socket"
require "yaml"

module PuavoRest

fqdn = Socket.gethostbyname(Socket.gethostname).first

if ENV["RACK_ENV"] == "test"
  CONFIG = {
    "ldap" => fqdn,
    "ltsp_server_data_dir" => "/tmp/puavo-rest-test",
    "bootserver" => true,
    "server" => {
      :username => "cucumber",
      :password => "cucumber"
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
      "bootserver" => true,
      "server" => {
        :username => PUAVO_ETC.ldap_dn,
        :password => PUAVO_ETC.ldap_password
      }
    }
  end
end
end
