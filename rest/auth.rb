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

  def is_dn(s)
    # Could be slightly better I think :)
    # but usernames should have no commas or equal signs
    s && s.include?(",") && s.include?("=")
  end

  # Create ldap connection
  #
  # @param credentials [Hash]
  # @option credentials [Symbol] :dn ldap dn
  # @option credentials [Symbol] :password plain text password
  # @see #new_model
  def create_ldap_connection(credentials)
    ldap_conn = LDAP::Conn.new(CONFIG["ldap"])
    ldap_conn.set_option(LDAP::LDAP_OPT_PROTOCOL_VERSION, 3)
    ldap_conn.start_tls

    if credentials[:dn]
      dn = credentials[:dn]
    elsif is_dn(credentials[:username])
      dn = credentials[:username]
    elsif credentials[:username]
      dn = resolve_dn(credentials[:username])
    end

    logger.info "#{ self.class.name } Bind with #{ credentials[:username] } #{ dn }"
    begin
      if credentials[:sasl]
        ldap_conn.sasl_quiet = true
        ldap_conn.sasl_bind('', 'GSSAPI')
      else
        ldap_conn.bind(dn, credentials[:password])
      end
    rescue LDAP::ResultError
      raise BadCredentials, "Bad username/dn or password"
    end

    return ldap_conn
  end

  def basic_auth
    return if not env["HTTP_AUTHORIZATION"]
    type, data = env["HTTP_AUTHORIZATION"].split(" ")
    if type == "Basic"
      plain = Base64.decode64(data)
      username, password = plain.split(":")
      return create_ldap_connection(
        :username => username,
        :password => password
      )
    end
  end

  # If PuavoRest is running on a boot server use the credentials of the server.
  # Can be used to make public resources on the school network.
  def boot_server
    return if CONFIG["bootserver"].nil?

    # In future we will only use Bootserver based authentication if
    # 'Authorization: Bootserver' is set. Otherwise we will assume Kerberos
    # authentication.
    if env["HTTP_AUTHORIZATION"] != "Bootserver"
      logger.warn "DEPRECATED! Header 'Authorization: Bootserver' is missing from bootserver authenticated resource"
    end

    if c = CONFIG["bootserver_override"]
      return create_ldap_connection(
        :username => c[:username],
        :password => c[:password]
      )
    else
      return create_ldap_connection(
        :username => PUAVO_ETC.ldap_dn,
        :password => PUAVO_ETC.ldap_password
      )
    end
  end

  KRB_LOCK = Mutex.new

  def kerberos
    # TODO: locks!
    return if env["HTTP_AUTHORIZATION"].nil?
    auth_key = env["HTTP_AUTHORIZATION"].split()[0]
    return if auth_key.downcase != "negotiate"

    started = Time.now
    conn = nil

    KRB_LOCK.synchronize do

      input_token = Base64.decode64(env["HTTP_AUTHORIZATION"].split()[1])
      kg = Krb5Gssapi.new(CONFIG["fqdn"], CONFIG["keytab"])

      begin
        kg.copy_ticket(input_token)
      rescue GSSAPI::GssApiError => err
        if err.message.match(/Clock skew too great/)
          raise KerberosError, :user => "Your clock is messed up"
        else
          raise err
        end
      rescue Krb5Gssapi::NoDelegation => err
        raise KerberosError, :user =>
          "Credentials are not delegated! '--delegation always' missing?"
      end

      logger.info "Creating LDAP connection using Kerberos for #{ kg.display_name }"
      conn = create_ldap_connection(:sasl => true)
      kg.clean_up

      logger.info "SASL bind with Kerberos took #{ Time.now - started } seconds"
    end

    return conn
  end

  def auth(*auth_methods)

    auth_methods.each do |method|
      if conn = send(method)
        LdapHash.setup(:connection => conn)
        logger.info "Auth: Using #{ method }"
        break
      end
    end

    if not LdapHash.connection?
      headers "WWW-Authenticate" => "Negotiate"
      halt 401, json(:error => {
        :message => "Could not create ldap connection. Bad/missing credentials.",
        :methods => auth_methods
      })
    end
  end

end
end
