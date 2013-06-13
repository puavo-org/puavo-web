require "ldap"
require "json"
require "multi_json"
require "sinatra/base"
require "sinatra/json"
require "base64"
require "debugger" if Sinatra::Base.development?

require_relative "./credentials"
require_relative "./ldap_model"
require_relative "./ldap_hash"
require_relative "./ldap_sinatra"
require_relative "./resources/external_files"
require_relative "./resources/users"
require_relative "./resources/schools"
require_relative "./resources/devices"
require_relative "./resources/organisations"
require_relative "./resources/sessions"

# @!macro route
#   @overload $0 $1
#   @method $0_$1 $1
#   @return [HTTP response]


# Puavo Rest module
module PuavoRest

class Root < LdapSinatra
  set :public_folder, "public"

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
