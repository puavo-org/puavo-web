module Puavo
  module Helpers

    def rest_proxy
      LdapOrganisation.current.rest_proxy
    end

    def external_pw_mgmt_url
      Puavo::Organisation.
        find(LdapOrganisation.current.cn).
        value_by_key("external_pw_mgmt_url")

    end

    def new_group_management?(school)
      new_group_management = Puavo::Organisation.
        find(LdapOrganisation.current.cn).
        value_by_key("new_group_management")

      return false unless new_group_management

      return false if new_group_management["enable"] != true

      return true unless new_group_management["only_of_schools"]

      new_group_management["only_of_schools"].include?(school.puavoId)
    end


    def users_synch?(school)
      users_synch = Puavo::Organisation.
        find(LdapOrganisation.current.cn).
        value_by_key("users_synch")

      return false unless users_synch

      return false if users_synch["enable"] != true

      return true unless users_synch["only_of_schools"]

      users_synch["only_of_schools"].include?(school.puavoId)
    end
  end
end
