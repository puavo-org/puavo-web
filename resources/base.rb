
module PuavoRest

module ErrorMethods

  # Halt request with not_found code
  # @param msg [String] Human readable description of the situation
  # @return [JSON] Error message { "error": { "code": ... } }
  def bad_credentials(msg="")
    json_format(401, "bad_credentials", msg)
  end

  # Halt request with not_found code
  # @param msg [String] Human readable description of the situation
  # @return [JSON] Error message { "error": { "code": ... } }
  def not_found(msg="")
    json_format(404, "not_found", msg)
  end

  private

  def json_format(status, code, msg)
    halt status, {"Content-Type" => "application/json"}, {
      "error" => {
        "code" => code,
        "message" => msg
      }
    }.to_json
  end

end

# Abstract Sinatra application base
# @author Esa-Matti Suuronen
class LdapBase < Sinatra::Base

  include ErrorMethods
  helpers Sinatra::JSON

  not_found do
    not_found "Cannot find resource from #{ request.path }"
  end

  before do

    cred = request.env["PUAVO_CREDENTIALS"]
    if not cred
      bad_credentials "No credentials supplied"
    end

    @ldap_conn = LDAP::Conn.new("precise64.opinsys.net")
    @ldap_conn.set_option(LDAP::LDAP_OPT_PROTOCOL_VERSION, 3)
    @ldap_conn.start_tls

    begin
      @ldap_conn.bind(cred[:username], cred[:password])
    rescue LDAP::ResultError
      bad_credentials("Bad username or password")
    end

  end

end

end
