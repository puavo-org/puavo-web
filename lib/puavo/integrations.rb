# Third-party systems integration "badges" and other stuff

module Puavo
  module Integrations
    # Retrieves various third-party system integrations for the specified
    # school in the *current* organisation. The school ID *MUST* be an
    # integer, not a string!
    def get_integrations_for_school(school_id)
      # No integration definitions -> nothing to display, even if
      # integration data exists for this organisation and school
      return [] if Puavo::INTEGRATION_DEFINITIONS.empty?

      # The cache assumes that school IDs are unique across organisations,
      # so this lookup won't yet need the name of the current organisation
      return INTEGRATIONS_CACHE[school_id] if INTEGRATIONS_CACHE.include?(school_id)

      # Get the per-school integration data, if it exists
      integrations = Puavo::ORGANISATION_INTEGRATIONS.fetch(LdapOrganisation.current.cn, {})

      # The raw organisation-level data (in Puavo::ORGANISATION_INTEGRATIONS)
      # looks like this:
      #
      #    hogwarts:
      #      schools:
      #        global: all_schools_have_this_integration
      #        12345: some_integration
      #        67890: another_integration, third_integration
      #      schedule:
      #        some_integration:
      #          hours: "5"
      #          minutes: "0"
      #        another_integration:
      #          hours: "1,2"
      #          minutes: "5,15"
      #        third_integration:
      #          hours: "07-17"
      #          minutes: "15"
      #
      # We use the organisation name and the school ID to pick the target school
      # from the 'schools' block and scheduling data from 'schedule', and
      # process and cache the results.

      # Use per-school settings if they're defined, otherwise use global settings
      schools = integrations.fetch('schools', {})
      schedule = integrations.fetch('schedule', {})

      if schools.include?(school_id)
        # Integrations are listed for this school
        names = schools[school_id]
      elsif schools.include?('global')
        # No integrations for this school, but a global list exists
        names = schools['global']
      else
        # No integrations available at all
        names = ''
      end

      # Split the string and clean it up by removing unknown definitions and dupes
      names = names.split(',')
      names.each { |n| n.strip! }
      names.reject! { |i| !Puavo::INTEGRATION_DEFINITIONS.keys.include?(i) }
      names.uniq!

      # Get a list of integrations for this school
      integrations = []

      names.each do |name|
        d = Puavo::INTEGRATION_DEFINITIONS[name]

        hours = nil
        minutes = nil

        if schedule.include?(name)
          # TODO: Parse these so we can display the next synchronisation
          # time in the UI.
          hours = schedule[name].fetch('hours', nil)
          minutes = schedule[name].fetch('minutes', nil)
        end

        integrations << {
          name: d.name,
          pretty_name: d.pretty_name,
          type: d.type,
          hours: hours,
          minutes: minutes
        }
      end

      # Sort the integrations by pretty name
      integrations.sort! do |a, b|
        a[:pretty_name].downcase <=> b[:pretty_name].downcase
      end

      # You need to restart the server anyway for any changes to
      # organisations.yml and integrations.yml to apply, so it's
      # safe to cache these
      INTEGRATIONS_CACHE[school_id] = integrations
      integrations
    end

    # 'integration_name' is a string that contains a word like "primus" or "gsuite"
    def school_has_integration?(school_id, integration_name)
      integrations = get_integrations_for_school(school_id)

      integrations.each do |i|
        # linear searches are not nice, but most schools that have integrations
        # have only 1 or 2 of them
        return true if i[:name] == integration_name
      end

      false
    end

    private

    # Cache for school PuavoID -> integration data, so we don't have to
    # constantly parse the raw data from the YML files
    INTEGRATIONS_CACHE = {}
  end
end
