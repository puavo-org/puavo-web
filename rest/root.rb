require_relative "./puavo-rest"

#   @overload $0 $1
#   @method $0_$1 $1
#   @return [HTTP response]


module PuavoRest
DEB_PACKAGE = Array(`dpkg -l | grep puavo-rest`.split())[2]
VERSION = File.open("VERSION", "r"){ |f| f.read }.strip
GIT_COMMIT = File.open("GIT_COMMIT", "r"){ |f| f.read }.strip
STARTED = Time.now

FLOG = FluentWrap.new(
  "puavo-rest",
  :hostname => Socket.gethostname,
  :version => "#{ VERSION } #{ GIT_COMMIT }"
)

FLOG.info "starting"

class BeforeFilters < LdapSinatra
  enable :logging

  before do
    ip = env["HTTP_X_REAL_IP"] || request.ip
    response.headers["X-puavo-rest-version"] = "#{ VERSION } #{ GIT_COMMIT }"

    begin
      client_hostname = Resolv.new.getname(ip)
    rescue Resolv::ResolvError
      client_hostname = ""
    end

    logger.info "#{ env["REQUEST_METHOD"] } #{ request.path } by #{ ip } (#{ client_hostname })"

    port = [80, 443].include?(request.port) ? "": ":#{ request.port }"

    request_host = request.host.to_s.gsub(/^staging\-/, "")

    LdapModel.setup(
      :organisation => Organisation.by_domain(request_host) || Organisation.default_organisation_domain!,
      :rest_root => "#{ request.scheme }://#{ request.host }#{ port }"
    )

    self.flog = FLOG.merge(
      :organisation_key => Organisation.current.organisation_key,
      :bootserver => !!CONFIG["bootserver"],
      :cloud => !!CONFIG["cloud"],
      :request => {
        :url => request.url,
        :method => env["REQUEST_METHOD"],
        :client_hostname => client_hostname,
        :ip => ip
      }
    )
    flog.info "request"
  end

  after do
    unhandled_exception = nil

    if env["sinatra.error"]
      err = env["sinatra.error"]
      if err.kind_of?(JSONError)
        flog.info "request rejected", :reason => err.as_json
      else
        unhandled_exception = {
          :error => {
            :uuid => (0...25).map{ ('a'..'z').to_a[rand(26)] }.join,
            :code => err.class.name,
            :message => err.message
          }
        }
        flog.error(
          "unhandled exception",
          unhandled_exception.merge(:backtrace => err.backtrace)
        )
      end
    end


    LdapModel.clear_setup
    LocalStore.close_connection
    self.flog = nil
    if unhandled_exception && ENV["RACK_ENV"] == "production"
      time = Time.now.to_s
      puts "Unhandled exception #{ err.class.name }: '#{ err }' at #{ time } (#{ time.to_i })"
      puts err.backtrace
      halt 500, json(unhandled_exception)
    end

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

  get "/v3/about" do
    json({
      "git_commit" => GIT_COMMIT,
      "version" => VERSION,
      "deb_packge" => DEB_PACKAGE,
      "uptime" => (Time.now - STARTED).to_i
    })
  end

  use BeforeFilters

  use PuavoRest::PrinterQueues
  use PuavoRest::WlanNetworks
  use PuavoRest::ExternalFiles
  use PuavoRest::Users
  use PuavoRest::Devices
  use PuavoRest::BootConfigurations
  use PuavoRest::Sessions
  use PuavoRest::Organisations

  if CONFIG["cloud"]
    use PuavoRest::SSO
  end

  if CONFIG["bootserver"]
    use PuavoRest::LtspServers
    use PuavoRest::BootServers
  end
end
end
