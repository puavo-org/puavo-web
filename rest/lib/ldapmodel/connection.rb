require "syslog"
Syslog.open("puavo-rest(slapd)", Syslog::LOG_PID, Syslog::LOG_DAEMON | Syslog::LOG_LOCAL3)

# Connection management
class LdapModel

  class LdapHashError < Exception; end

  KRB_LOCK = Mutex.new

  # Do LDAP sasl bind with a kerberos ticket
  def self.sasl_bind(ticket)
    conn = LDAP::Conn.new(CONFIG["ldap"])
    conn.set_option(LDAP::LDAP_OPT_PROTOCOL_VERSION, 3)
    conn.sasl_quiet = true
    conn.start_tls
    KRB_LOCK.synchronize do
      begin
        kg = Krb5Gssapi.new(CONFIG["fqdn"], CONFIG["keytab"])
        kg.copy_ticket(ticket)
        username, org = kg.display_name.split("@")
        settings[:credentials][:username] = username
        LdapModel.setup(:organisation => PuavoRest::Organisation.by_domain(org.downcase))
        conn.sasl_bind('', 'GSSAPI')
      rescue GSSAPI::GssApiError => err
        if err.message.match(/Clock skew too great/)
          raise KerberosError, :user => "Your clock is messed up"
        else
          raise KerberosError, :user => err.message
        end
      rescue Krb5Gssapi::NoDelegation => err
        raise KerberosError, :user =>
          "Credentials are not delegated! \'--delegation always\' missing?"
      ensure
        kg.clean_up
      end
    end
    conn
  end


  # Do LDAP bind with dn and password
  # @param dn [String]
  # @param password [String]
  def self.dn_bind(dn, pw)
    conn = LDAP::Conn.new(CONFIG["ldap"])
    conn.set_option(LDAP::LDAP_OPT_PROTOCOL_VERSION, 3)
    conn.start_tls
    conn.bind(dn, pw)
    conn
  end

  # Create connection for LdapModel
  def self.create_connection
    raise "Cannot create connection without credentials" if settings[:credentials].nil?
    credentials = settings[:credentials]
    conn = nil

    if credentials[:kerberos]
      return sasl_bind(credentials[:kerberos])
    end

    if credentials[:dn].to_s.strip.empty?
      raise BadCredentials, "DN missing" if not credentials[:dn]
    end

    if credentials[:password].to_s.strip.empty?
      raise BadCredentials, "Password missing" if not credentials[:password]
    end

    begin
        conn = dn_bind(credentials[:dn], credentials[:password])
    rescue LDAP::ResultError => err
      if err.message == "Invalid credentials"
        raise BadCredentials, {
          :msg => "Invalid credentials (dn/pw)",
          :meta => {
            :dn => credentials[:dn],
            :username => credentials[:username]
        }}
      else
        raise LdapError, "Other LDAP error: #{ err.message }"
      end
    end

    if conn.nil?
        raise LdapError, "ldap bind returned nil instead of connection"
    end

    return conn
  end

  def self.settings
    Thread.current[:ldap_hash_settings] || { :credentials_cache => {} }
  end

  def self.settings=(settings)
    Thread.current[:ldap_hash_settings] = settings
  end

  # Configure LDAP bind for LdapModel
  #
  # @param opts [Hash]
  # @option opts [Hash] :credentials
  #   Credentials for LDAP bind. Must have `:dn` and `:password`
  #   or `:kerberos`.
  # @option opts [PuavoRest::Organisation] :organisation
  # @option opts [Hash] :rest_root puavo-rest mount point url
  #
  # @param &block [Block] If block is passed the configuration is active only during the exection of the block
  def self.setup(opts, &block)
    prev = self.settings
    self.settings = prev.merge(opts)

    if opts[:credentials]
      self.settings[:credentials_cache] = {}
    end

    if block
      res = block.call
      self.settings = prev
    end
    res
  end

  def self.connection
    if conn = settings[:credentials_cache][:current_connection]
      return conn
    end
    if settings[:credentials]
      settings[:credentials_cache][:current_connection] = create_connection
    end
  end


  # Return true if an organisation is configured
  # @return PuavoRest::Organisation
  def self.organisation?
    !!settings[:organisation]
  end

  # Get configured organisation
  # @return String
  def self.organisation
    if settings[:organisation].nil?
      raise BadInput, :user => "Cannot configure organisation for this request"
    else
      settings[:organisation]
    end
  end

  def self.clear_setup
    if settings[:credentials_cache] && settings[:credentials_cache][:current_connection]
      settings[:credentials_cache][:current_connection].unbind()
    end

    self.settings = nil
  end

  # ruby-ldap operation wrapper
  #
  # The raw ruby-ldap gives very little information on errors. So wrap it and
  # add a lot more details to the error wrapper.
  #
  # Log start and end of the operation to syslog. It should make it lot
  # easier to see which slapd log messages are related to the ruby-ldap
  # operation. Slapd logs levels must be raised in order the take advantage of
  # this.
  #
  # Convert LDAP::ResultError: "No such object" errors to nil return values to
  # make it consistent with every other not found error.
  #
  # Each operation are given an UUID so the user response, puavo-rest log and
  # syslog logs can be combined
  #
  def self.ldap_op(method, *args, &block)
    res = nil
    ldap_op_uuid = (0...25).map{('a'..'z').to_a[rand(10)] }.join

    Syslog.log(Syslog::LOG_NOTICE, "START(#{ ldap_op_uuid })> #{ connection.class }##{ method } #{ args.inspect }")
    err = nil

    begin
      res = connection.send(method, *args, &block)
    rescue Exception => _err
      err = _err

      # not really an error. Just convert to nil response
      return if is_not_found?(err)

      message = "\n#{ err.class }: #{ err }\n\n    was raised by\n\n"
      message += "UUID: #{ ldap_op_uuid }\n"
      message += "#{ connection.class }##{ method }(#{ args.map{|a| a.inspect }.join(", ")})\n"

      raise LdapError, {
        :user => "#{ err.class }: #{ err.message } (grep syslog for #{ ldap_op_uuid })",
        :message => message,
        :op_uuid => ldap_op_uuid,
        :original_error => err,
        :args => args,
        :method => method
      }
    ensure
      end_msg = "OK"
      if err
        end_msg = " ERROR: #{ err.class } #{ err.message }"
      end
      Syslog.log(Syslog::LOG_NOTICE, "END(#{ ldap_op_uuid })> #{ end_msg }")
    end

    res
  end

  def self.is_not_found?(err)
    !!(err && err.class == LDAP::ResultError && err.message == "No such object")
  end

  def link(path)
    self.class.settings[:rest_root] + path
  end


end
