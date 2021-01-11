Encoding.default_external = Encoding::UTF_8

require_relative "./puavo-rest"
require_relative "./lib/mailer"

module PuavoRest
DEB_PACKAGE = Array(`dpkg -l | grep puavo-rest`.split())[2]
VERSION = File.open("VERSION", "r"){ |f| f.read }.strip
GIT_COMMIT = File.open("GIT_COMMIT", "r"){ |f| f.read }.strip
STARTED = Time.now
HOSTNAME = Socket.gethostname
FQDN = Socket.gethostbyname(Socket.gethostname).first

# Use $rest_flog only when not in sinatra routes.
# Sinatra routes have a "flog" method which automatically
# logs the route and user.
$rest_flog_base = RestLogger.new(
  :hostname => HOSTNAME,
  :fqdn => FQDN,
  :version => "#{ VERSION } #{ GIT_COMMIT }",
)

$rest_flog = $rest_flog_base.merge({})

$mailer = PuavoRest::Mailer.new

@@test_boot_server_dn = nil

def self.test_boot_server_dn
  @@test_boot_server_dn
end

def self.test_boot_server_dn=(dn)
  @@test_boot_server_dn = dn
end

UUID_ALPHABET = ('a'..'z').to_a.freeze

class BeforeFilters < PuavoSinatra
  before do
    $rest_flog = $rest_flog_base.merge({})

    LdapModel::PROF.reset

    # Ensure that any previous connections are cleared. Each request must
    # provide their own credentials.
    LdapModel.clear_setup

    @req_start = Time.now
    ip = env["HTTP_X_REAL_IP"] || request.ip

    begin
      @client_hostname = Resolv.new.getname(ip)
    rescue Resolv::ResolvError
    end

    port = [80, 443].include?(request.port) ? "": ":#{ request.port }"

    request_host = request.host.to_s.gsub(/^staging\-/, "")

    organisation = Organisation.by_domain(request_host)
    if organisation.nil? && CONFIG["bootserver"]
      organisation = Organisation.default_organisation_domain!
    end

    if organisation.nil? then
      $rest_flog_base.warn("cannot determine the organisation for host '#{ request.host.to_s }'")
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

    self.flog = $rest_flog = $rest_flog_base.merge(log_meta)
    flog.info('handling request...')
  end

  after do
    LdapModel::PROF.print_search_count("#{ env["REQUEST_METHOD"] } #{ request.path }")
    LdapModel::PROF.reset

    request_duration = (Time.now - @req_start).to_f
    self.flog = self.flog.merge :request_duration => request_duration

    unhandled_exception = nil

    if env["sinatra.error"]
      err = env["sinatra.error"]
      if err.kind_of?(JSONError) || err.kind_of?(Sinatra::NotFound)
        flog.warn("... request rejected (in #{ request_duration } seconds): #{ err.message }")
      else
        unhandled_exception = {
          :error => {
            :uuid => UUID_ALPHABET.sample(25).join,
            :code => err.class.name,
            :message => err.message
          }
        }

        flog.error("UNHANDLED EXCEPTION (UUID #{unhandled_exception[:error][:uuid]}): #{err.message}")

        Array(err.backtrace).reverse.each do |b|
          flog.error(b)
        end
      end
    else
      flog.info("... request done (in #{ request_duration } seconds).")
    end

    LdapModel.clear_setup
    LocalStore.close_connection
    self.flog = nil
    if unhandled_exception then
      halt 500, json(unhandled_exception)
    end
  end
end

class Root < PuavoSinatra
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

  get "/v3/ldap_connection_test" do
    LdapModel.setup(:credentials => CONFIG["server"]) do
      # Just try get something from the ldap. This does not find anything but
      # raises LdapError if the connection fails
      User.by_username("noone")
    end
    json({:ok => true})
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
  use PuavoRest::DeviceImages
  use PuavoRest::Schools
  use PuavoRest::BootServers
  use PuavoRest::UserLists
  use PuavoRest::SambaNextRid
  use PuavoRest::Groups
  use PuavoRest::Authentication
  use PuavoRest::ExternalLogins
  use PuavoRest::BootserverDNS
  use PuavoRest::MySchoolUsers

  if CONFIG["cloud"]
    use PuavoRest::SSO
    use PuavoRest::Certs
  end

  if CONFIG["password_management"]
    use PuavoRest::Password
    use PuavoRest::EmailConfirm
  end

end
end
