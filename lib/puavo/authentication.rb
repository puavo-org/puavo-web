module Puavo
  module Authentication
    def self.included(base)
      base.send :extend, ClassMethods
    end


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

    module ClassMethods

      def dn_cache_key(uid)
        "user_dn:#{ uid }"
      end

      def delete_caches(uid)
        Rails.cache.delete dn_cache_key uid
      end

      def uid_to_dn(uid)
        if uid.nil? || uid.empty?
          raise UnknownUID, "Cannot get dn from empty or nil uid"
        end

        logger.debug "Looking up dn for #{ uid }"
        dn = Rails.cache.fetch dn_cache_key(uid) do
          # On cache miss we need to use the Puavo credentials from config/ldap.yml
          # to fetch the user object which contains the user dn.

          # This find call actually initializes the LDAP connection under the
          # hood with Puavo credentials.
          user = self.find(:first, :attribute => "uid", :value => uid)

          if user
            user.dn.to_s
          else
            nil
          end
        end

        raise UnknownUID, "Cannot get dn for #{ uid }" if not dn
        logger.debug "Found #{ dn } for #{ uid }"
        return dn
      end


      def find_by_uid(uid)
        self.find uid_to_dn uid
      end


      # Authenticate dn to LDAP and make ActiveLdap to use these credentials in
      # future connections.
      #
      # Raises AuthenticationFailed if connection could not be made.
      # Returns possible admin permissions on successful connect
      def authenticate(user_dn, password)

        if user_dn.nil?
          logger.info "Login failed: Bad dn"
          raise AuthenticationFailed, "Bad dn"
        end

        # Remove previous connection
        self.remove_connection

        # Setup new ActiveLdap connections to use user's credentials
        LdapBase.ldap_setup_connection(
          LdapBase.configuration[:host],
          LdapBase.base.to_s,
          user_dn.to_s,
          password)

        # Do not never ever allow anonymous connections in Puavo. Should be
        # false in config/ldap.yml, but we just make sure here.
        self.connection.instance_variable_set :@allow_anonymous, false

        # This is the first time when LDAP connection is used with the user's
        # credentials. So this search call will initialize the connection and
        # will raise ActiveLdap::AuthenticationError if user supplied a
        # bad password.
        begin
          return School.search(
            :filter => "(puavoSchoolAdmin=#{user_dn})",
            :scope => :one, :attributes => ["puavoId"],
            :limit => 1 )
        rescue ActiveLdap::AuthenticationError
          raise AuthenticationFailed, "Bad dn or password"
        end

      end

      def authorize(user_dn, password)

        user_dn = ActiveLdap::DistinguishedName.parse user_dn.to_s

        admin_permissions = authenticate user_dn, password

        # Authorize school admins
        if not admin_permissions.empty?
          logger.info "Authorization ok: Admin #{ user_dn }"
          return user_dn
        end

        # Authorize OAuth users
        if user_dn.rdns[0].keys[0] == "puavoOAuthAccessToken"
          logger.info "Authorization ok: OAuth #{ user_dn }"
          return user_dn
        end

        # Authorize External Services
        if user_dn.rdns[1]["ou"] == "System Accounts"
          logger.info "Authorization ok: External Service #{ user_dn }"
          return user_dn
        end

        # Authorize organisation owners
        organisation = LdapOrganisation.first
        if organisation && organisation.owner && organisation.owner.include?(user_dn)
          logger.info "Authorization ok: Organisation owner #{ user_dn }"
          return user_dn
        end

        raise AuthorizationFailed, "Unauthorized access"
      end
    end
  end
end
