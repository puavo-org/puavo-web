module Puavo
  module Helpers

    def rest_proxy(*args)
      LdapOrganisation.current.rest_proxy(*args)
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

    # Returns [true, domain] if automatic (enforced) email addresses are enabled in this organisation.
    # If enabled, all email addresses are formatted as "username@domain".
    def get_automatic_email_addresses
      if test_environment? && ENV['AUTOMATIC_EMAIL_ADDRESSES'] == 'enabled'
        # Since this is organisation-wide, we cannot enable it in all tests. Tests for
        # these are run with separate commands that temporarily enable these.
        return [true, 'hogwarts.magic']
      end

      automatic = Puavo::Organisation.find(LdapOrganisation.current.cn).
        value_by_key('automatic_email_addresses')

      return [false, nil] unless automatic

      # Make the domain nil by default, so if it hasn't been specified, things will crash
      return [automatic.fetch('enabled', false), automatic.fetch('domain', nil)]
    end

    def get_yml_organisation
      @yml_organisation ||= Puavo::Organisation.find(LdapOrganisation.current.cn)
      @yml_organisation
    end

    def get_organisation_intl_timezone
      org = LdapOrganisation.current

      # If the organisation has a configured timezone, use it
      return org.puavoTimezone if org.puavoTimezone

      # Is there a timezone specified for this organisation in organisations.yml?
      yml_timezone = get_yml_organisation.value_by_key('intl_timezone')
      return yml_timezone if yml_timezone

      # Use the default
      'Europe/Helsinki'
    end

    def get_organisation_intl_locale
      org = LdapOrganisation.current

      # If the organisation has a configured locale, use it
      return org.puavoLocale.gsub('_', '-').gsub('.UTF-8', '') if org.puavoLocale

      # Look up the locale from organisations.yml
      yml_timezone = get_yml_organisation.value_by_key('intl_locale')
      return yml_timezone if yml_timezone

      # Use the default
      'fi-FI'
    end

    # Takes an LDAP timestamp (a single-element array containing a string usually formatted as
    # "YYYYMMDDHHMMSSZ" or "YYYYMMDDHHMMSS+offset") and returns it as a UTC Time object
    def self.ldap_time_string_to_utc_time(t)
      t ? Time.strptime(t[0], '%Y%m%d%H%M%S%z').utc : nil
    rescue
      nil
    end

    # Like above, but returns a Unixtime stamp
    def self.ldap_time_string_to_unixtime(t)
      t ? ldap_time_string_to_utc_time(t).to_i : nil
    rescue
      nil
    end

    # Converts LDAP operational timestamp attribute (received with search_as_utf8() call)
    # to unixtime. Expects the timestamp to be nil or a single-element array. Used in
    # users, groups and devices controllers when retrieving data with AJAX calls.
    def self.convert_ldap_time(t)
      return nil unless t
      Time.strptime(t[0], '%Y%m%d%H%M%S%z').to_i
    end

    def self.convert_ldap_time_pick_date(t)
      return nil unless t
      Time.strptime(t[0], '%Y%m%d%H%M%S%z').to_date.to_time.to_i
    end

    # Given a list of Puavo-OS desktop image file names and their release names, formats them so
    # that the JavaScript tables can display and filter them nicely
    def self.get_release_name(image_file_name, releases)
      return nil unless image_file_name

      image_file_name.gsub!('.img', '')

      {
        file: image_file_name,
        release: releases.fetch(image_file_name, nil),
      }
    end

  end
end
