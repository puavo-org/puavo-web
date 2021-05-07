module Puavo
  module Helpers

    def rest_proxy(*args)
      LdapOrganisation.current.rest_proxy(*args)
    end

    # Returns true if the specified user (in the current organisation) has any
    # extra permissions granted for them
    def can_schooladmin_do_this?(username, action)
      permissions = Puavo::Organisation.find(LdapOrganisation.current.cn).
                      value_by_key('schooladmin_permissions')
      return false unless permissions

      extra = permissions.fetch('by_username', {}).fetch(username, {})

      return extra.include?(action.to_s) && extra[action.to_s] == true
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

    def show_language_selector?
      Puavo::Organisation.find(LdapOrganisation.current.cn).value_by_key('show_language_selector') || true
    end

    # Used to detect testing environments. Unfortunately there are some legacy tests that simply
    # won't work with the new JavaScript -based indexes and tools, and we must serve them the old
    # legacy indexes and pages. This is something that should be fixed with new tests, but I gave
    # up on trying to make the test system run JavaScript. I'm sure it can be done, but I really
    # have no idea how. None of the examples and tutorials I read helped.
    def test_environment?
      ENV['RAILS_ENV'] == 'test'
    end

    # Converts LDAP operational timestamp attribute (received with search_as_utf8() call)
    # to unixtime. Expects the timestamp to be nil or a single-element array. Used in
    # users, groups and devices controllers when retrieving data with AJAX calls.
    def self.convert_ldap_time(t)
      return nil unless t
      Time.strptime(t[0], '%Y%m%d%H%M%S%z').to_i
    end

  end
end
