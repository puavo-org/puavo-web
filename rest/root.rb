require_relative "./puavo-rest"
require_relative "./lib/mailer"

#   @overload $0 $1
#   @method $0_$1 $1
#   @return [HTTP response]


module PuavoRest
DEB_PACKAGE = Array(`dpkg -l | grep puavo-rest`.split())[2]
VERSION = File.open("VERSION", "r"){ |f| f.read }.strip
GIT_COMMIT = File.open("GIT_COMMIT", "r"){ |f| f.read }.strip
STARTED = Time.now
HOSTNAME = Socket.gethostname
FQDN = Socket.gethostbyname(Socket.gethostname).first
REDIS_CONNECTION = Redis.new CONFIG["redis"].symbolize_keys

def self.about
  return ({
      "git_commit" => GIT_COMMIT,
      "hostname" => HOSTNAME,
      "fqdn" => HOSTNAME,
      "version" => VERSION,
      "deb_package" => DEB_PACKAGE,
      "uptime" => (Time.now - STARTED).to_i
  })
end

# Use only when not in sinatra routes. Sinatra routes have a "flog" method
# which automatically logs the route and user
$rest_flog = FluentWrap.new(
  "puavo-rest",
  :hostname => HOSTNAME,
  :fqdn => FQDN,
  :version => "#{ VERSION } #{ GIT_COMMIT }",
  :deb_package => DEB_PACKAGE
)

$rest_flog.info "starting"

$mailer = PuavoRest::Mailer.new

@@test_boot_server_dn = nil

def self.test_boot_server_dn
  @@test_boot_server_dn
end

def self.test_boot_server_dn=(dn)
  @@test_boot_server_dn = dn
end

class BeforeFilters < LdapSinatra
  enable :logging

  before do
    LdapModel::PROF.reset
    @req_start = Time.now
    ip = env["HTTP_X_REAL_IP"] || request.ip
    response.headers["X-puavo-rest-version"] = "#{ VERSION } #{ GIT_COMMIT }"

    begin
      @client_hostname = Resolv.new.getname(ip)
    rescue Resolv::ResolvError
    end

    logger.info "#{ env["REQUEST_METHOD"] } #{ request.path } by #{ ip } (#{ @client_hostname })"

    port = [80, 443].include?(request.port) ? "": ":#{ request.port }"

    request_host = request.host.to_s.gsub(/^staging\-/, "")

    organisation = Organisation.by_domain(request_host)
    if organisation.nil? && CONFIG["bootserver"]
      organisation = Organisation.default_organisation_domain!
    end

    if organisation.nil?
      logger.warn "Cannot to get organisation for hostname #{ request.host.to_s }"
    end


    LdapModel.setup(
      :organisation => organisation,
      :rest_root => "#{ request.scheme }://#{ request.host }#{ port }"
    )

    request_headers = request.env.select{|k,v| k.start_with?("HTTP_")}
    if request_headers["HTTP_AUTHORIZATION"]
      request_headers["HTTP_AUTHORIZATION"] = "[FILTERED]"
    end

    log_meta = {
      :bootserver => !!CONFIG["bootserver"],
      :cloud => !!CONFIG["cloud"],
      :rack_env => ENV["RACK_ENV"],
      :req_uuid => UUID.generate,
      :request => {
        :url => request.url,
        :headers => request_headers,
        :path => request.path,
        :method => env["REQUEST_METHOD"],
        :client_hostname => @client_hostname,
        :ip => ip
      }
    }
    if Organisation.current?
      log_meta[:organisation_key] = Organisation.current.organisation_key
    end

    self.flog = $rest_flog.merge(log_meta)
    flog.info "request start"

  end

  after do

    LdapModel::PROF.print_search_count("#{ env["REQUEST_METHOD"] } #{ request.path }")
    LdapModel::PROF.reset

    request_duration = (Time.now - @req_start).to_f
    self.flog = self.flog.merge :request_duration => request_duration
    flog.info "request"

    if env["sinatra.error"]
      err = env["sinatra.error"]
      if err.kind_of?(JSONError) || err.kind_of?(Sinatra::NotFound)
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

  get "/v3/slow_test" do
    sleep 2
    "I was slow"
  end

  get "/v3/ldap_connection_test" do
    # Just try get something from the ldap
    LdapModel.setup(:credentials => CONFIG["server"]) do
      has_orgs = Organisation.all.size > 0
      if !has_orgs
        status 500
      end
      has_orgs.to_s
    end
  end

  get "/v3/about" do
    json(PuavoRest.about)
  end

  use BeforeFilters

  use PuavoRest::ScheduledJobs
  use PuavoRest::PrinterQueues
  use PuavoRest::WlanNetworks
  use PuavoRest::ExternalFiles
  use PuavoRest::Users
  use PuavoRest::Devices
  use PuavoRest::BootConfigurations
  use PuavoRest::Sessions
  use PuavoRest::Organisations
  use PuavoRest::FluentRelay
  use PuavoRest::DeviceImages
  use PuavoRest::Schools
  use PuavoRest::BootServers
  use PuavoRest::LegacyRoles

  if CONFIG["cloud"]
    use PuavoRest::SSO
  end

  if CONFIG["bootserver"]
    use PuavoRest::LtspServers
  end

  if CONFIG["password_management"]
    use PuavoRest::Password
    use PuavoRest::EmailConfirm
  end

end
end
