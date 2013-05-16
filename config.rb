require "socket"
require "yaml"

module PuavoRest
begin
  CONFIG = YAML.load_file "/etc/puavo-rest.yml"
rescue Errno::ENOENT
  # Do automatc configuration on boot servers
  require "puavo/etc"
  fqdn = Socket.gethostbyname(Socket.gethostname).first
  CONFIG = {
    "ldap" => fqdn,
    "ltsp_server_data_dir" => "/run/puavo-rest",
    "bootserver" => true
  }
end
end
