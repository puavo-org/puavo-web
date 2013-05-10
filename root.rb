require "ldap"
require "json"
require "multi_json"
require "sinatra/base"
require "sinatra/json"
require "base64"
require "yaml"

require "./credentials"
require "./errors"
require "./resources/base"
require "./resources/external_files"
require "./resources/users"


# @!macro route
#   @overload $0 $1
#   @method $0_$1 $1
#   @return [HTTP response]

module PuavoRest

begin
  CONFIG = YAML.load_file "/etc/puavo-rest.yml"
rescue Errno::ENOENT
  # Do automatc configuration on boot servers
  CONFIG = {
    "ldap" => PUAVO_ETC.domain,
    "bootserver" => true
  }
end

class Root < LdapSinatra

  get "/" do
    "hello"
  end

  use PuavoRest::ExternalFiles
  use PuavoRest::Users
end
end
