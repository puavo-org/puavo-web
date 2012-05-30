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

    attr_accessor :authenticated, :authorized, :dn, :host, :base

    def self.remove_connection
      ActiveLdap::Base.active_connections.keys.each do |connection_name|
        ActiveLdap::Base.remove_connection(connection_name)
      end
    end

    def configure_ldap_connection(dn, password, host, base)
      # Remove previous connection
      self.class.remove_connection
      logger.info "Configuring ActiveLdap to use dn '#{ dn }' on '#{ host }' with '#{ base }'"

      @dn = dn
      @password = password
      @host = host
      @base = base

      # Setup new ActiveLdap connections to use user's credentials
      LdapBase.ldap_setup_connection @host, @base.to_s, @dn.to_s, @password

      # Do not never ever allow anonymous connections in Puavo. Should be
      # false in config/ldap.yml, but we just make sure here.
      LdapBase.connection.instance_variable_set :@allow_anonymous, false

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
          :filter => "(puavoSchoolAdmin=#{@dn})",
          :scope => :one, :attributes => ["puavoId"],
          :limit => 1 )
      rescue ActiveLdap::AuthenticationError
        raise AuthenticationFailed, "Bad dn or password"
      end

      @authenticated = true

    end

    def external_service?
      @dn.rdns[1]["ou"] == "System Accounts"
    end

    # Authorize that user has permissions to use Puavo
    def authorize

      raise AuthorizationFailed, "Cannot authorize before authenticating" unless @authenticated

      # Authorize school admins
      if not @admin_permissions.empty?
        logger.info "Authorization ok: Admin #{ @dn }"
        return @authorized = true
      end

      # Authorize External Services
      if external_service?
        logger.info "Authorization ok: External Service #{ @dn }"
        return @authorized = true
      end

      # Authorize organisation owners
      organisation = LdapOrganisation.first
      if organisation && organisation.owner && organisation.owner.include?(@dn)
        logger.info "Authorization ok: Organisation owner #{ @dn }"
        return @authorized = true
      end

      raise AuthorizationFailed, "Unauthorized access for #{ @dn }"
    end

    def current_user

      # TODO: find user object with puavoOAuthAccessToken
      if @dn.to_s.starts_with? "puavoOAuthAccessToken"
        logger.warn "Cannot get User object for #{ @dn }"
        return
      end

      if external_service?
        # ExternalService has no permission to find itself.
        # @current_user ||= ExternalService.find @dn
      else
        @current_user ||= User.find @dn
      end
    end

    def logger
      RAILS_DEFAULT_LOGGER
    end

  end
end
