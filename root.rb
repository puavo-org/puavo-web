require "ldap"
require "json"
require "multi_json"
require "sinatra/base"
require "sinatra/json"
require "base64"
require "debugger" if Sinatra::Base.development?

require "./credentials"
require "./errors"
require "./resources/base"
require "./resources/external_files"
require "./resources/users"
require "./resources/ltsp_servers"


# @!macro route
#   @overload $0 $1
#   @method $0_$1 $1
#   @return [HTTP response]


# Simple logger
def log(msg)
  STDERR.puts(Time.now.to_s + ": " + msg)
end

# Puavo Rest module
module PuavoRest

class Root < LdapSinatra

  get "/" do
    "hello"
  end

  use PuavoRest::ExternalFiles
  use PuavoRest::Users
  if CONFIG["bootserver"]
    require "./resources/ltsp_servers"
    use PuavoRest::LtspServers
  end
end
end
