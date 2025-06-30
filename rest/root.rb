Encoding.default_external = Encoding::UTF_8

require 'socket'
require 'securerandom'

require_relative "./puavo-rest"
require_relative "./lib/mailer"

module PuavoRest
DEB_PACKAGE = Array(`dpkg -l | grep puavo-rest`.split())[2]
VERSION = File.open("VERSION", "r"){ |f| f.read }.strip
GIT_COMMIT = File.open("GIT_COMMIT", "r"){ |f| f.read }.strip
STARTED = Time.now
HOSTNAME = Socket.gethostname
FQDN = Addrinfo.getaddrinfo(Socket.gethostname, nil).first.getnameinfo.first

# Silence "rb_tainted_str_new is deprecated and will be removed in Ruby 3.2" and
# "rb_tainted_str_new_cstr is deprecated and will be removed in Ruby 3.2" warnings.
# They don't come from our code, they appear to originate from ruby-ldap, a library
# which was last updated in July 2018. Running the full puavo-rest test suite will
# produce around *44 megabytes* of these warnings and they drown out all other
# messages. As of June 2024, we're not fully sure what do to about this problem,
# but fixing the gem or replacing it with another gem have been discussed about.
Warning[:deprecated] = false

# Use $rest_log only when not in sinatra routes.
# Sinatra routes have a "rlog" method which automatically
# logs the route and user.
$rest_log_base = RestLogger.new(
  :hostname => HOSTNAME,
  :fqdn => FQDN,
  :version => "#{ VERSION } #{ GIT_COMMIT }",
)

$rest_log = $rest_log_base.merge({})

$mailer = PuavoRest::Mailer.new

@@test_boot_server_dn = nil

def self.test_boot_server_dn
  @@test_boot_server_dn
end

def self.test_boot_server_dn=(dn)
  @@test_boot_server_dn = dn
end

UUID_ALPHABET = ('a'..'z').to_a.freeze

# Returns true if this user (username) is "super owner", ie. an owner user who has
# been granted extra permissions. Usually these users are employees of the company
# that makes Puavo.
def self.super_owner?(name)
  begin
    # The filename is hardcoded, because the puavo-rest server dos already contain
    # some puavo-web's files, including this file, and it's always in /etc/puavo-web
    super_owners = File.read('/etc/puavo-web/super_owners.txt').split("\n")
  rescue StandardError => e
    $rest_log.error("ERROR: Can't query the super owner status: #{e}")
    super_owners = []
  end

  super_owners.include?(name)
end

class BeforeFilters < PuavoSinatra
  before do
    $rest_log = $rest_log_base.merge({})

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
      $rest_log_base.warn("cannot determine the organisation for host '#{ request.host.to_s }'")
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

    self.rlog = $rest_log = $rest_log_base.merge(log_meta)
    rlog.info('handling request...')
  end

  after do
    LdapModel::PROF.print_search_count("#{ env["REQUEST_METHOD"] } #{ request.path }")
    LdapModel::PROF.reset

    request_duration = (Time.now - @req_start).to_f
    self.rlog = self.rlog.merge :request_duration => request_duration

    unhandled_exception = nil

    if env["sinatra.error"]
      err = env["sinatra.error"]
      if err.kind_of?(JSONError) || err.kind_of?(Sinatra::NotFound)
        rlog.warn("... request rejected (in #{ request_duration } seconds): #{ err.message }")
      else
        unhandled_exception = {
          :error => {
            :uuid => UUID_ALPHABET.sample(25).join,
            :code => err.class.name,
            :message => err.message
          }
        }

        rlog.error("UNHANDLED EXCEPTION (UUID #{unhandled_exception[:error][:uuid]}): #{err.message}")

        Array(err.backtrace).reverse.each do |b|
          rlog.error(b)
        end
      end
    else
      rlog.info("... request done (in #{ request_duration } seconds).")
    end

    LdapModel.clear_setup
    LocalStore.close_connection
    self.rlog = nil
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
  use PuavoRest::ExternalLogins
  use PuavoRest::BootserverDNS
  use PuavoRest::MySchoolUsers
  use PuavoRest::EmailManagement
  use PuavoRest::OAuth2::OpenIDConnect

  if CONFIG["cloud"]
    use PuavoRest::SSO
    use PuavoRest::Certs
  end

  if CONFIG["password_management"]
    use PuavoRest::Password
  end

  if CONFIG['mfa_management']
    use PuavoRest::MFAManagement
  end

  if CONFIG['citrix']
    use PuavoRest::Citrix
  end

end
end
