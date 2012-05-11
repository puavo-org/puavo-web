module Puavo
  module Authentication
    def self.included(base)
      base.send :extend, ClassMethods
    end

    # Works like the User object from ActiveLdap, but only for the dn method.
    # Real user object can fetched with real_user if needed.
    #
    # TODO: We could simulate the real user object lazily with method_missing,
    # but Puavo does not currently use this object too much from here so there
    # is no really a need for it yet.
    class LazyUser

      def initialize(dn)
        @dn = dn
      end

      def dn
        @dn
      end

      def real_user
        User.find dn
      end

    end

    module ClassMethods

      def dn_cache_key(login_uid)
        "user_dn:#{ login_uid }"
      end

      def delete_caches(login_uid)
        Rails.cache.delete dn_cache_key login_uid
      end

      def authenticate(login, password)

        # To authenticate an user we need to make a LDAP bind with user's dn
        # and password. Lets look it up from cache:
        user_dn = Rails.cache.fetch dn_cache_key(login) do
          # On cache miss we need to use the Puavo credentials from config/ldap.yml
          # to fetch the user object which contains the user dn.

          # This find call actually initializes the LDAP connection under the
          # hood with those credentials.
          user = self.find(:first, :attribute => "uid", :value => login)
          # Remove connection made with Puavo credentials
          user.remove_connection
          user.dn
        end

        user = LazyUser.new user_dn

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
            :filter => "(puavoSchoolAdmin=#{user_dn}d)",
            :scope => :one, :attributes => ["puavoId"],
            :limit => 1 )
        rescue ActiveLdap::AuthenticationError
          logger.info "Login failed for #{ login } (#{ user_dn }): Bad password"
          return false
        end

        # Allow authentication always if logged in user is ExteralService object
        if user.class == ExternalService
          return user
        end

        # Allow authentication if user is  a school admin in the some school.
        if not admin_permissions.empty?
          return user
        end

        # Allow authentication if user is an organisation owner
        organisation = LdapOrganisation.first
        if organisation && organisation.owner.include?(user_dn)
          return user
        end

        logger.info "Login failed for #{ login } (#{ user_dn }): Not school admin or organisation owner"
        return false
      end
    end
  end
end
