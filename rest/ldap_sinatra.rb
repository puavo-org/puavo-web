module PuavoRest

# Abstract Sinatra base class which add ldap connection to instance scope
class LdapSinatra < Sinatra::Base

  helpers Sinatra::JSON
  set :json_encoder, :to_json
  enable :logging

  # Respond with a text content
  def txt(text)
    content_type :txt
    halt 200, text.to_s
  end

  # In routes handlers use limit query string to slice arrays
  #
  # Example: /foos?limit=2
  #
  # @param a [Array] Array to slice
  def limit(a)
    if params["limit"]
      a[0...params["limit"].to_i]
    else
      a
    end
  end


  # Resolve username using the credentials
  def resolve_dn(username)

    if LdapHash.organisation.nil?
      raise LdapHash::InternalError, "Cannot resolve username to dn before organisation is set!"
    end

    conn = create_ldap_connection(
      :dn => PUAVO_ETC.ldap_dn,
      :password => PUAVO_ETC.ldap_password
    )

    res = LdapHash.with(:connection => conn) do
      User.by_username(username)["dn"]
    end

    conn.unbind
    res
  end

  def is_dn(s)
    # Could be slightly better I think :)
    # but usernames should have no commas or equal signs
    s.include?(",") && s.include?("=")
  end

  # Acquire credentials using the specified auth classes
  # @see auth
  def acquire_credentials(klasses)
    credentials = nil

    klasses.each do |auth_klass|
      credentials = auth_klass.new.call(request.env)
      next if credentials.nil?

      if is_dn(credentials[:username])
        credentials[:dn] = credentials[:username]
      else
        credentials[:dn] = resolve_dn(credentials[:username])
      end

      logger.info "#{ self.class.name } got credentials using #{ auth_klass.name }"
      break if credentials
    end

    if credentials.nil?
      raise LdapHash::BadCredentials, "Cannot find credentials using #{ klasses.inspect }"
    end

    credentials
  end

  def auth(*klasses)
    credentials = acquire_credentials(klasses)
    LdapHash.setup(:connection => create_ldap_connection(credentials))
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

    logger.info "#{ self.class.name } Bind with #{ credentials[:dn] } (#{ credentials[:username] })"
    begin
      ldap_conn.bind(credentials[:dn], credentials[:password])
    rescue LDAP::ResultError
      raise LdapHash::BadCredentials, "Bad username/dn or password"
    end
  end

  # Render LdapHash::LdapHashError classes as nice json responses
  error LdapHash::LdapHashError do |err|
    logger.warn err
    halt err.code, json(:error => { :message => err.message })
  end


end
end
