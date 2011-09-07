module Puavo
  module Authentication
    def self.included(base)
      base.send :extend, ClassMethods
    end

    module ClassMethods
      def authenticate(login, password)
        logger.debug "Find user by uid from ldap"
        logger.debug "uid: #{login}"

        begin
          user = self.find(:first, :attribute => "uid", :value => login)

          if user.bind(password)
            host = LdapBase.configuration[:host]
            base = LdapBase.base.to_s
            user.remove_connection
            LdapBase.ldap_setup_connection(host, base, user.dn, password)

            # Allow authentication always if logged in user is ExteralService object
            if user.class == ExternalService
              return user
            end

            # Allow authetication only if user is School Admin in the some School or organisation owner.
            if School.find( :first, :attribute => "puavoSchoolAdmin", :value => user.dn ) ||
                LdapOrganisation.first.owner.include?(user.dn)
              return user
            end
          end
        rescue Exception => e
          logger.info "Login failed: login: #{login}, Exception: #{e}"
          return false
        end
      end
    end
  end
end
