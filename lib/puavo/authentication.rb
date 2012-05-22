module Puavo
  module Authentication
    def self.included(base)
      base.send :extend, ClassMethods
    end


    module ClassMethods

      def dn_cache_key(login_uid)
        "user_dn:#{ login_uid }"
      end

      def delete_caches(login_uid)
        Rails.cache.delete dn_cache_key login_uid
      end

      # Authenticate user with login username and password.
      # Returns user dn string on successful login or false on invalid login
      def authenticate(login, password)

        # To authenticate an user we need to make a LDAP bind with user's dn
        # and password. Lets look it up from cache:
        user_dn = Rails.cache.fetch dn_cache_key(login) do
          # On cache miss we need to use the Puavo credentials from config/ldap.yml
          # to fetch the user object which contains the user dn.

          # This find call actually initializes the LDAP connection under the
          # hood with Puavo credentials.
          user = self.find(:first, :attribute => "uid", :value => login)

          # Remove connection made with Puavo credentials
          self.remove_connection

          if user.nil?
            return nil
          end

          user.dn
        end

        if user_dn.nil?
          logger.info "Login failed for #{ login }: Unknown username"
          return false
        end

        # Setup new ActiveLdap connections to use user's credentials
        LdapBase.ldap_setup_connection(
          LdapBase.configuration[:host],
          LdapBase.base.to_s,
          user_dn,
          password)

        # Do not never ever allow anonymous connections in Puavo. Should be
        # false in config/ldap.yml, but we just make sure here.
        self.connection.instance_variable_set :@allow_anonymous, false

        # This is the first time when LDAP connection is used with the user's
        # credentials. So this search call will initialize the connection and
        # will raise ActiveLdap::AuthenticationError if user supplied a
        # bad password.
        begin
          admin_permissions = School.search(
            :filter => "(puavoSchoolAdmin=#{user_dn})",
            :scope => :one, :attributes => ["puavoId"],
            :limit => 1 )
        rescue ActiveLdap::AuthenticationError
          logger.info "Login failed for #{ login } (#{ user_dn }): Bad password"
          return false
        end

        # Allow authentication if user is  a school admin in the some school.
        if not admin_permissions.empty?
          return user_dn
        end

        # Allow authentication if user is an organisation owner
        organisation = LdapOrganisation.first
        if organisation && organisation.owner.include?(user_dn)
          return user_dn
        end

        # Allow authentication always if logged in user an external service
        if user_dn.rdns[1]["ou"] == "System Accounts"
          return user_dn
        end

        logger.info "Login failed for #{ login } (#{ user_dn }): Not school admin or organisation owner"
        return false
      end
    end
  end
end
