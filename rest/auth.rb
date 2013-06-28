require "puavo"

require "thread"
require "base64"
require "gssapi"
require "gssapi/lib_gssapi"

require_relative "./lib/krb5-gssapi"

module PuavoRest

class LdapSinatra < Sinatra::Base


  # Resolve username using the credentials
  def resolve_dn(username)

    if LdapHash.organisation.nil?
      raise JSONError, INTERNAL_ERROR, "Cannot resolve username to dn before organisation is set!"
    end

    conn = create_ldap_connection(
      :dn => PUAVO_ETC.ldap_dn,
      :password => PUAVO_ETC.ldap_password
    )

    res = LdapHash.with(:connection => conn) do
      user = User.by_username(username)
      raise BadCredentials, "No such username #{ username }" if not user
      user["dn"]
    end

    conn.unbind
    res
  end


  def basic_auth
    return if not env["HTTP_AUTHORIZATION"]
    type, data = env["HTTP_AUTHORIZATION"].split(" ")
    if type == "Basic"
      plain = Base64.decode64(data)
      username, password = plain.split(":")

      credentials = { :password => password  }
      if LdapHash.is_dn(username)
        credentials[:dn] = username
      else
        credentials[:username] = username
      end
      logger.info "Using Basic Auth #{ credentials[:dn] ? "with dn" : "with uid" }"
      return credentials
    end
  end

  def server_auth
    return if CONFIG["bootserver"].nil?

    # In future we will only use server based authentication if 'Authorization:
    # Bootserver' is set. Otherwise we will assume Kerberos authentication.
    if env["HTTP_AUTHORIZATION"] != "Bootserver"
      logger.warn "DEPRECATED! Header 'Authorization: Bootserver' is missing from server auth"
    end

    return CONFIG["server"]
  end


  def kerberos
    return if env["HTTP_AUTHORIZATION"].nil?
    auth_key = env["HTTP_AUTHORIZATION"].split()[0]
    return if auth_key.downcase != "negotiate"
    logger.info "Using Kerberos authentication"
    return {
      :kerberos => Base64.decode64(env["HTTP_AUTHORIZATION"].split()[1])
    }
  end

  def auth(*auth_methods)

    auth_methods.each do |method|
      if credentials = send(method)
        LdapHash.setup(:credentials => credentials)
        break
      end
    end

    if not LdapHash.connection
      headers "WWW-Authenticate" => "Negotiate"
      halt 401, json(:error => {
        :message => "Could not create ldap connection. Bad/missing credentials.",
        :methods => auth_methods
      })
    end
  end

end
end
