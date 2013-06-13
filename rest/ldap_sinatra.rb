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


  @@auth_config = {}

  # Define classes that are used to get credentials for this resource
  #
  # @param auth_klass [Class] Authentication class
  # @param options [Hash] Options hash.
  # @option options [Symbol] :skip
  #   Skip credentials lookup on HTTP method(s). Possible values: :get, :post:,
  #   :put, :patch, :options
  def self.auth(auth_klass, options={})
    (@@auth_config[self] ||= []).push([auth_klass, options])
  end



  # Acquire credentials using the specified auth classes
  # @see auth
  def acquire_credentials
    (@@auth_config[self.class] || []).each do |auth|
      auth_klass, options = auth
      if cred = auth_klass.new.call(request.env, options)
        return cred
      end
    end
    nil
  end

  # Setup ldap connection
  # @param credentials [Hash]
  # @option credentials [Symbol] :username username (dn)
  # @option credentials [Symbol] :password plain text password
  # @see #new_model
  def setup_ldap_connection(credentials)
    ldap_conn = LDAP::Conn.new(CONFIG["ldap"])
    ldap_conn.set_option(LDAP::LDAP_OPT_PROTOCOL_VERSION, 3)
    ldap_conn.start_tls

    begin
      ldap_conn.bind(credentials[:username], credentials[:password])
    rescue LDAP::ResultError
      bad_credentials("Bad username or password")
    end
  end

  before "/v3/*" do
    credentials = acquire_credentials

    @organisation_info = (
      LdapModel.organisations_by_domain[request.host] ||
      LdapModel.organisations_by_domain["*"]
    )

    if credentials and @ldap_conn.nil?
      @ldap_conn = setup_ldap_connection(credentials)
    end

    LdapHash.setup(
      :connection => @ldap_conn,
      :organisation => @organisation_info
    )
  end

  after do
    LdapHash.clear_setup
    if @ldap_conn
      # TODO: unbind connection
    end
  end

  # Render LdapHash::LdapHashError classes as nice json responses
  error LdapHash::LdapHashError do |err|
    halt err.code, json(:error => { :message => err.message })
  end


  # Assert that authentication is required for this route even if the the ldap
  # connection is not actually used
  def require_auth
    if not @ldap_conn
      bad_credentials "No credentials supplied"
    end
  end

  # Model instance factory
  # Create new model instance with the current organisation info and ldap
  # connection
  #
  # @param klass [Model class]
  # @return [Model instance]
  def new_model(klass)
    if @ldap_conn
      klass.new(@ldap_conn, @organisation_info)
    else
      bad_credentials "No credentials supplied"
    end
  end

end

end
