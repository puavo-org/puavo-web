require "ldap"
require "json"
require "multi_json"
require "sinatra/base"
require "sinatra/json"
require "base64"
require "debugger" if Sinatra::Base.development?

require_relative "./credentials"
require_relative "./errors"
require_relative "./resources/base"
require_relative "./resources/external_files"
require_relative "./resources/users"
require_relative "./resources/schools"
require_relative "./resources/devices"
require_relative "./resources/sessions"

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
  use PuavoRest::Devices
  use PuavoRest::Sessions
  if CONFIG["bootserver"]
    require_relative "./resources/ltsp_servers"
    use PuavoRest::LtspServers
  end
end
end
