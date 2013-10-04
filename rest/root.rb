
require_relative "./puavo-rest"

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
    LocalStore.close_connection
  end
end

class Root < LdapSinatra
  use SuppressJSONError
  set :public_folder, "public"

  not_found do
    json({
      :error => {
        :code => "UnknownResource",
        :message => "Unknown resource"
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
    use PuavoRest::BootServers
  end
end
end
