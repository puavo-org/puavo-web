require "ldap"
require "json"
require "multi_json"
require "sinatra/base"
require "sinatra/json"
require "base64"
require "gssapi"
require "gssapi/lib_gssapi"
require "debugger" if Sinatra::Base.development?

require_relative "./auth"
require_relative "./lib/ldap_converters"
require_relative "./ldap_hash"
require_relative "./ldap_sinatra"
require_relative "./resources/external_files"
require_relative "./resources/users"
require_relative "./resources/schools"
require_relative "./resources/devices"
require_relative "./resources/organisations"
require_relative "./resources/sessions"
require_relative "./resources/wlan_networks"
require_relative "./resources/remote_auth"


#   @overload $0 $1
#   @method $0_$1 $1
#   @return [HTTP response]


module PuavoRest

class BeforeFilters < LdapSinatra

  before do
    ip = env["HTTP_X_REAL_IP"] || request.ip

    begin
      hostname = " (#{ Resolv.new.getname(ip) })"
    rescue Resolv::ResolvError
      hostname = ""
    end

    logger.info "#{ env["REQUEST_METHOD"] } #{ request.path } by #{ ip }#{ hostname }"

    port = [80, 443].include?(request.port) ? "": ":#{ request.port }"

    LdapHash.setup(
      :organisation =>
        Organisation.by_domain[request.host] || Organisation.by_domain["*"],
      :rest_root => "#{ request.scheme }://#{ request.host }#{ port }"
    )
  end

  after do
    LdapHash.clear_setup
  end
end

class Root < LdapSinatra
  set :public_folder, "public"

  use BeforeFilters
  use PuavoRest::ExternalFiles
  use PuavoRest::Users
  use PuavoRest::Devices
  use PuavoRest::WlanNetworks
  use PuavoRest::RemoteAuth
  use PuavoRest::Organisations if Sinatra::Base.development?
  if CONFIG["bootserver"]
    require_relative "./resources/ltsp_servers"
    use PuavoRest::LtspServers
    use PuavoRest::Sessions
  end
end
end
