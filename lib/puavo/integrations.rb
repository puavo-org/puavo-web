# Third-party systems integration stuff

module Puavo
  module Integrations
    # Retrieves various third-party system integrations for the specified school
    # The school ID *MUST* be an integer, not a string!
    def get_integrations_for_school(school_id)
      return [] if Puavo::INTEGRATION_DEFINITIONS.empty?
      return INTEGRATIONS_CACHE[school_id] if INTEGRATIONS_CACHE.include?(school_id)

      integrations = get_organisation_integrations

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

      # You need to restart the server anyway for any changes to organisations.yml
      # to apply, so it's safe to cache these
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

    INTEGRATIONS_CACHE = {}

    # Retrieve the per-organisation integration configuration
    def get_organisation_integrations
      conf = Puavo::Organisation.
        find(LdapOrganisation.current.cn).
        value_by_key("integrations")

      conf || {}
    end
  end
end
