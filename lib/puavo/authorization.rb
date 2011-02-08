module Puavo
  module Authorization
    def self.current_user
      Thread.current["current_user"]
    end
    
    def self.current_user=(user)
      Thread.current["current_user"] = user
      # Update owners list
      Thread.current["owners"] = LdapOrganisation.current.owner
    end

    def self.organisation_owner?
      if Puavo::Authorization.current_user && Thread.current["owners"]
        return Thread.current["owners"].include?(Puavo::Authorization.current_user.dn)
      end
      return false
    end
  end
end
