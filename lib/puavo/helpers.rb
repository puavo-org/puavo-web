module Puavo
  module Helpers

    def rest_proxy
      LdapOrganisation.current.rest_proxy
    end


    def new_group_management?(school)
      new_group_management = Puavo::Organisation.
        find(LdapOrganisation.current.cn).
        value_by_key("new_group_management")

      return false if new_group_management["enable"] != true

      return true unless new_group_management["only_of_schools"]

      new_group_management["only_of_schools"].include?(school.puavoId)
    end
  end
end
