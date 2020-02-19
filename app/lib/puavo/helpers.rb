module Puavo
  module Helpers

    def rest_proxy(*args)
      LdapOrganisation.current.rest_proxy(*args)
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

    def get_organisation_password_requirements
      Puavo::Organisation.
        find(LdapOrganisation.current.cn).
        value_by_key('password_requirements')
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

    def supertable_sorting_locale
      # It's probably not a good idea to use Finnish collation by default in the long run,
      # but at the time I'm making this commit, "fi-FI" is the default and all others are
      # case-by-case exceptions that are overridden in the configuration file.
      begin
        Puavo::Organisation.find(LdapOrganisation.current.cn).value_by_key('sort_locale') || 'fi-FI'
      rescue
        'fi-FI'
      end
    end

    # Used to detect testing environments. Unfortunately there are some legacy tests that simply
    # won't work with the new JavaScript -based indexes and tools, and we must serve them the old
    # legacy indexes and pages. This is something that should be fixed with new tests, but I gave
    # up on trying to make the test system run JavaScript. I'm sure it can be done, but I really
    # have no idea how. None of the examples and tutorials I read helped.
    def test_environment?
      ENV['RAILS_ENV'] == 'test'
    end

  end
end
