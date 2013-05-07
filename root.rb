require "ldap"
require "json"
require "multi_json"
require "sinatra/base"
require "sinatra/json"
require "base64"

require "debugger"
require "pry"

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
class Root < LdapSinatra
  use PuavoRest::ExternalFiles
  use PuavoRest::Users
end
end
