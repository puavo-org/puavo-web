module Puavo
  module Helpers

    def rest_proxy
      LdapOrganisation.current.rest_proxy
    end
  end
end
