require "user_error"

module Puavo

  class AuthenticationError < UserError
    def code
      "authentication_error"
    end
  end

  class AuthenticationFailed < AuthenticationError
    def code
      "bad_credentials"
    end
  end

  class NoCredentials < AuthenticationError
    def code
      "no_credentials"
    end
  end

  class AuthorizationFailed < AuthenticationError
    def code
      "no_permissions"
    end
  end


  # For User model
  module AuthenticationMixin
    # FIXME Observer?
    def delete_dn_cache
      organisation_key = LdapOrganisation.first.cn.to_s
      Rails.cache.delete Puavo::Authentication.dn_cache_key organisation_key, uid
    end
  end

  class Authentication

    attr_accessor :authenticated, :authorized

    def self.dn_cache_key(organisation_key, uid)
      "user_dn:#{ organisation_key }:#{ uid }"
    end

    def initialize
      @credentials = {}
    end

    [:dn, :organisation_key, :scope, :password].each do |attr|
      define_method attr do
        @credentials[attr]
      end
    end

    def puavo_configuration
      ActiveLdap::Base.ensure_configuration
    end

    def base
      return current_organisation.ldap_base
    end

    def ldap_host
      @credentials[:ldap_host] || puavo_configuration["host"]
    end

    def self.remove_connection
      ActiveLdap::Base.active_connections.keys.each do |connection_name|
        ActiveLdap::Base.remove_connection(connection_name)
      end
    end

    def uid_to_dn(uid)

      if uid.match(/^service\//)
        uid = uid.match(/^service\/(.*)/)[1]
        user_class = LdapService
      else
        user_class = User
      end

      user_dn = Rails.cache.fetch self.class.dn_cache_key(organisation_key, uid) do
        # Remove previous connection
        self.class.remove_connection
        LdapBase.ldap_setup_connection( ldap_host,
                                        base.to_s,
                                        puavo_configuration["bind_dn"],
                                        puavo_configuration["password"] )

        user = user_class.find(:first, :attribute => "uid", :value => uid)

        if user
          user.dn.to_s
        else
          nil
        end
      end

      if not user_dn
        raise AuthenticationFailed, "Cannot get dn for UID '#{ uid }'"
      end

      return ActiveLdap::DistinguishedName.parse user_dn
    end

    def configure_ldap_connection(credentials)
      credentials = credentials.dup

      # Newer versions of activeldap fail with syntax errors if the UID field
      # is empty. Ensure we got either the DN or username before continuing.
      raise AuthenticationError, "username/dn is empty" if credentials[:dn].to_s.empty? and credentials[:uid].to_s.empty?

      if credentials[:dn]
        credentials[:dn] = ActiveLdap::DistinguishedName.parse(credentials[:dn])
      end

      @credentials = credentials

      if current_organisation.nil?
        raise Puavo::AuthenticationError, "Bad organisation"
      end

      if uid = @credentials[:uid]
        @credentials[:dn] = uid_to_dn(uid)
      end

      # Reset attributes on new configuration
      @current_user = nil
      @authenticated = false
      @authorized = false

      # Remove previous connection
      self.class.remove_connection

      logger.info "Configuring ActiveLdap to use #{ @credentials.select{ |a,b| a != :password }.map { |k,v| "#{ k }: #{ v }" }.join ", " }"
      logger.debug "PW: #{ @credentials[:password] }" if ENV["LOG_LDAP_PASSWORD"]

      # Setup new ActiveLdap connections to use user's credentials
      LdapBase.ldap_setup_connection(
        ldap_host,
        base.to_s,
        @credentials[:dn],
        @credentials[:password]
      )


      # ExternalService is on o=puavo database. So use always uid=puavo for it.
      ExternalService.ldap_setup_connection(
        ldap_host,
        puavo_configuration["base"],
        puavo_configuration["bind_dn"],
        puavo_configuration["password"]
      )

      # Do not never ever allow anonymous connections in Puavo. Should be
      # false in config/ldap.yml, but we just make sure here.
      LdapBase.connection.instance_variable_set :@allow_anonymous, false

    end

    # Test dn&password bind to LDAP without actually configuring ActiveLdap to
    # use them
    def test_bind(dn, password)
      ldap = Net::LDAP.new(
        :host => ldap_host,
        :port => 389,
        :encryption => {
          :method => :start_tls
        },
        :auth => {
          :method => :simple,
          :username => dn.to_s,
          :password => password
      })

      if not ldap.bind
        raise AuthenticationFailed, "Test bind failed: Bad dn or password"
      end
    end

    # Authenticate configured connection to LDAP.
    #
    # Raises AuthenticationFailed if connection could not be made.
    # Returns possible admin permissions on successful connect
    def authenticate

      # This is the first time when LDAP connection is used with the user's
      # credentials. So this search call will initialize the connection and
      # will raise ActiveLdap::AuthenticationError if user supplied a
      # bad password.
      begin

        @admin_permissions = School.search(
          :filter => "(puavoSchoolAdmin=#{ dn })",
          :scope => :one, :attributes => ["puavoId"],
          :limit => 1 )


      rescue ActiveLdap::AuthenticationError
        raise AuthenticationFailed, "Bad dn or password"
      end


      @authenticated = true

    end

    def authenticated?
      !!@authenticated
    end

    def ldap_service?
      dn && dn.rdns[1]["ou"] == "System Accounts"
    end

    def server?
      dn && dn.rdns[1]["ou"] == "Servers"
    end

    def user?
      dn && dn.rdns[1]["ou"] == "People"
    end

    def device?
      dn && dn.rdns[1]["ou"] == "Devices"
    end

    # User is authenticated with real password
    def user_password?
      current_user.classes.include? "puavoEduPerson"
    end

    # Authorize that user has permissions to use Puavo
    def authorize

      raise AuthorizationFailed, "Cannot authorize before authenticating" unless @authenticated

      # Authorize school admins
      if not @admin_permissions.empty?
        logger.info "Authorization ok: Admin #{ dn }"
        return @authorized = true
      end

      # Authorize LDAP Services
      if ldap_service?
        logger.info "Authorization ok: LDAP Service #{ dn }"
        return @authorized = true
      end

      # XXX: This line if freaking slow!
      # Authorize organisation owners
      organisation = LdapOrganisation.first

      if organisation && organisation.owner && Array(organisation.owner).include?(dn)
        logger.info "Authorization ok: Organisation owner #{ dn }"
        return @authorized = true
      end

      # Authorize servers
      if server?
        logger.info "Authorization ok: Server #{ dn }"
        return @authorized = true
      end

      # Authorize devices
      if device?
        logger.info "Authorization ok: Device #{ dn }"
        return @authorized = true
      end

      raise AuthorizationFailed, "Unauthorized access for #{ dn }"
    end

    def current_user

      return @current_user if @current_user

      if ldap_service?
        @current_user = LdapService.find dn
      elsif user?
        @current_user = User.find dn
      else
        raise "Bad user type #{ dn.to_s }"
      end

      raise "Failed get User object for #{ dn }" if @current_user.nil?
      return @current_user
    end

    def current_organisation
      return if organisation_key.nil?
      org = Puavo::Organisation.find(organisation_key)
      if !org
        raise "#{ organisation_key.inspect } not in organisations.yml"
      end
      org
    end

    def logger
      Rails.logger
    end

  end
end
