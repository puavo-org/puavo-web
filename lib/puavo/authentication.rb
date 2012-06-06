module Puavo

  class AuthenticationError < UserError
  end

  # Bad username or password
  class AuthenticationFailed < AuthenticationError
  end

  # No permissions
  class AuthorizationFailed < AuthenticationError
  end

  class UnknownUID < UserError
  end

  # For User model
  module AuthenticationMixin

    def self.included(base)
      base.send :extend, ClassMethods
    end


    def delete_dn_cache
      Rails.cache.delete self.class.dn_cache_key uid
    end

    module ClassMethods

      def dn_cache_key(uid)
        "user_dn:#{ uid }"
      end

      def uid_to_dn(uid)
        if uid.nil? || uid.empty?
          raise UnknownUID, "Cannot get dn from empty or nil uid"
        end

        logger.debug "Looking up dn for #{ uid }"
        dn = Rails.cache.fetch dn_cache_key(uid) do

          user = self.find(:first, :attribute => "uid", :value => uid)

          if user
            user.dn.to_s
          else
            nil
          end
        end

        raise UnknownUID, "Cannot get dn for #{ uid }" if not dn
        logger.debug "Found #{ dn } for #{ uid }"
        return ActiveLdap::DistinguishedName.parse dn.to_s
      end

    end

  end

  class Authentication

    attr_accessor :authenticated, :authorized


    def initialize
      @credentials = {}
    end

    def dn
      @credentials[:dn]
    end

    def host
      @credentials[:host]
    end

    def base
      @credentials[:base]
    end

    def self.remove_connection
      ActiveLdap::Base.active_connections.keys.each do |connection_name|
        ActiveLdap::Base.remove_connection(connection_name)
      end
    end

    def configure_ldap_connection(credentials)

      @credentials.merge! credentials.symbolize_keys

      @credentials[:dn] = ActiveLdap::DistinguishedName.parse dn.to_s

      # Reset attributes on new configuration
      @current_user = nil
      @authenticated = false
      @authorized = false

      # Remove previous connection
      self.class.remove_connection



      logger.info "Configuring ActiveLdap to use #{ @credentials }"
      logger.debug "PW: #{ @credentials[:password] }" if ENV["LOG_LDAP_PASSWORD"]
      # Setup new ActiveLdap connections to use user's credentials
      LdapBase.ldap_setup_connection host, base.to_s, dn, @credentials[:password]

      # Do not never ever allow anonymous connections in Puavo. Should be
      # false in config/ldap.yml, but we just make sure here.
      LdapBase.connection.instance_variable_set :@allow_anonymous, false
    end

    # Test dn&password bind to LDAP without actually configuring ActiveLdap to
    # use them
    def test_bind(dn, password)
      ldap = Net::LDAP.new(
        :host => host,
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

    def external_service?
      dn.rdns[1]["ou"] == "System Accounts"
    end

    def oauth_client?
      dn.rdns.first.keys.first == "puavoOAuthClientId"
    end

    def oauth_token?
      dn.rdns[0].keys[0] == "puavoOAuthTokenId"
    end

    # Authorize that user has permissions to use Puavo
    def authorize

      raise AuthorizationFailed, "Cannot authorize before authenticating" unless @authenticated

      # Authorize school admins
      if not @admin_permissions.empty?
        logger.info "Authorization ok: Admin #{ dn }"
        return @authorized = true
      end

      # Authorize External Services
      if external_service?
        logger.info "Authorization ok: External Service #{ dn }"
        return @authorized = true
      end

      # Authorize OAuth Access Tokens
      if oauth_token?
        return @authorized = true
      end

      # Authorize organisation owners
      organisation = LdapOrganisation.first
      if organisation && organisation.owner && organisation.owner.include?(dn)
        logger.info "Authorization ok: Organisation owner #{ dn }"
        return @authorized = true
      end

      raise AuthorizationFailed, "Unauthorized access for #{ dn }"
    end

    def current_user

      raise "Cannot get current user before authentication" if not @authenticated

      return @current_user if @current_user


      if external_service?
        @current_user = ExternalService.find dn
      elsif oauth_token?
        access_token = AccessToken.find dn
        @current_user = User.find access_token.puavoOAuthEduPerson
      else
        @current_user = User.find dn
      end

      raise "Failed get User object for #{ dn }" if @current_user.nil?
      return @current_user
    end

    def logger
      RAILS_DEFAULT_LOGGER
    end

  end
end
