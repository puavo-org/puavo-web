require 'net/ldap'
require 'net/ldap/auth_adapter/gssapi'
require 'openssl'
require 'syslog'

Syslog.open("puavo-rest(slapd)", Syslog::LOG_PID, Syslog::LOG_DAEMON | Syslog::LOG_LOCAL3)

# Connection management
class LdapModel

  KRB_LOCK = Mutex.new

  # Do LDAP SASL bind with a kerberos ticket
  def self.sasl_bind(credentials)
    ticket = credentials[:kerberos]

    KRB_LOCK.synchronize do
      kg = nil

      begin
        kg = Krb5Gssapi.new(CONFIG['fqdn'], CONFIG['keytab'])
        kg.copy_ticket(ticket)

        username, org = kg.display_name.split('@')
        settings[:credentials][:username] = username
        LdapModel.setup(organisation: PuavoRest::Organisation.by_domain(org.downcase))

        ldap = Net::LDAP.new(
          host: ldap_server,
          port: 389,
          encryption: {
            method: :start_tls,
            tls_options: OpenSSL::SSL::SSLContext::DEFAULT_PARAMS,
          },
          auth: {
            method: :gssapi,
            hostname: ldap_server,
          }
        )

        bind_net_ldap(ldap, credentials)

        return ldap
      rescue GSSAPI::GssApiError => err
        if err.message.match(/Clock skew too great/)
          raise KerberosError, user: 'Your clock is messed up'
        else
          raise KerberosError, user: err.message
        end
      rescue Krb5Gssapi::NoDelegation
        raise KerberosError,
          user: "Credentials are not delegated! '--delegation always' missing?"
      ensure
        kg.clean_up if kg
      end
    end
  end

  # assumes that is called in context where settings[:credentials] exists
  def self.bind_net_ldap(ldap, credentials)
    return if ldap.bind

    result = ldap.get_operation_result
    case result.code
      when Net::LDAP::ResultCodeInvalidCredentials
        raise BadCredentials, {
          :msg => 'Invalid credentials',
          :meta => {
            :dn       => credentials[:dn],
            :username => credentials[:username],
          }
        }
      else
        raise LdapError,
              "Other LDAP error: #{ result.code } #{ result.message }"
    end
  end

  def self.dn_bind(credentials)
    ldap = Net::LDAP.new(
      host: ldap_server,
      port: 389,
      encryption: {
        method: :start_tls,
      },
      auth: {
        method: :simple,
        username: credentials[:dn],
        password: credentials[:password],
      }
    )

    bind_net_ldap(ldap, credentials)

    ldap
  end

  # Create connection for LdapModel
  def self.create_connection
    raise 'Cannot create connection without credentials' \
      if settings[:credentials].nil?
    credentials = settings[:credentials]
    conn = nil

    if credentials[:kerberos] then
      return sasl_bind(credentrials)
    end

    if credentials[:dn].to_s.strip.empty? then
      raise BadCredentials, "DN missing" if not credentials[:dn]
    end

    if credentials[:password].to_s.strip.empty? then
      raise BadCredentials, "Password missing" if not credentials[:password]
    end

    conn = dn_bind(credentials)

    if conn.nil? then
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

  # Get configured ldap server
  # @return String
  def self.ldap_server
    settings[:ldap_server] || CONFIG['ldap']
  end

  def self.disconnect
    # we use Net::LDAP in such a way that it does not keep the connection open
    settings[:credentials_cache][:current_connection] = nil
  end

  def self.clear_setup
    disconnect()
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
  ALPHABET = ('a'..'z').to_a.freeze

  def self.ldap_op(method, *args, &block)
    ldap_res = nil

    # Syslog.log(Syslog::LOG_DEBUG, "START(#{ ldap_op_uuid })> #{ connection.class }##{ method } #{ args.inspect }")
    err = nil

    begin
      connection.send(method, *args, &block)
      ldap_res = connection.get_operation_result
      case ldap_res.code
        when Net::LDAP::ResultCodeSuccess
          return ldap_res
        when Net::LDAP::ResultCodeNoSuchObject
          # Not really an error.  Just convert to nil response.
          return nil
        else
          raise LdapError,
                "ldap error: code=#{ ldap_res.code } #{ ldap_res.message }"
      end
    rescue StandardError => err
      ldap_op_uuid = ALPHABET.sample(25).join

      message = "\n#{ err.class }: #{ err }\n\n    was raised by\n\n"
      message += "UUID: #{ ldap_op_uuid }\n"
      message += "#{ connection.class }##{ method }(#{ args.map{|a| a.inspect }.join(", ")})\n"

      raise LdapError, {
        :args           => args,
        :message        => message,
        :method         => method,
        :op_uuid        => ldap_op_uuid,
        :original_error => err,
        :user           => "#{ err.class }: #{ err.message } (grep syslog for #{ ldap_op_uuid })",
      }
    ensure
      end_msg = 'OK'
      if err
        end_msg = " ERROR: #{ err.class } #{ err.message }"
      end
      # Syslog.log(Syslog::LOG_DEBUG, "END(#{ ldap_op_uuid })> #{ end_msg }")
    end
  end

  def link(path)
    self.class.settings[:rest_root] + path
  end
end
