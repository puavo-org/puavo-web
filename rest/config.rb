require "socket"
require "yaml"

module PuavoRest

fqdn = Socket.gethostbyname(Socket.gethostname).first

if ENV["RACK_ENV"] == "test"
  CONFIG = {
    "ldap" => fqdn,
    "ltsp_server_data_dir" => "/tmp/puavo-rest-test",
    "bootserver" => true
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
      "bootserver" => true
    }
  end
end
end
