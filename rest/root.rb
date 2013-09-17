require "ldap"
require "json"
require "multi_json"
require "sinatra/base"
require "sinatra/json"
require "base64"
require "gssapi"
require "gssapi/lib_gssapi"
require "debugger" if Sinatra::Base.development? || ENV["DEBUG"]

require_relative "./auth"
require_relative "./lib/ldap_converters"
require_relative "./ldap_hash"
require_relative "./ldap_sinatra"
require_relative "./resources/users"
require_relative "./resources/schools"
require_relative "./resources/organisations"
require_relative "./resources/printer_queues"
require_relative "./resources/sso"
require_relative "./resources/ltsp_servers"
require_relative "./resources/sessions"
require_relative "./resources/wlan_networks"
require_relative "./resources/external_files"
require_relative "./resources/devices"


#   @overload $0 $1
#   @method $0_$1 $1
#   @return [HTTP response]


module PuavoRest

class BeforeFilters < LdapSinatra
  enable :logging

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
  use SuppressJSONError
  set :public_folder, "public"

  not_found do
    json({
      :error => {
        :message => "Not found"
      }
    })
  end

  get "/" do
    "puavo-rest root"
  end

  get "/v3" do
    "puavo-rest v3 root"
  end

  get "/v3/error_test" do
    1 / 0
  end

  use BeforeFilters

  use PuavoRest::PrinterQueues
  use PuavoRest::WlanNetworks
  use PuavoRest::ExternalFiles
  use PuavoRest::Users
  use PuavoRest::Devices

  if CONFIG["cloud"]
    use PuavoRest::SSO
  end

  if CONFIG["bootserver"]
    use PuavoRest::LtspServers
    use PuavoRest::Sessions
    use PuavoRest::Organisations if Sinatra::Base.development?
  end
end
end
