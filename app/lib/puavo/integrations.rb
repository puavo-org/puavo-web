# Helper methods for third-party system integrations

require 'json'

module Puavo
  module Integrations
    # Caches integration data. Indexed by school puavoIds and the special "global" identifier.
    INTEGRATIONS_CACHE = {}

    # "Intelligently" merges two hashes. Hash 'b' can remove entries from 'a'
    # by setting the new value to nil. Nested hashes are handled recursively.
    def intelligent_merge(a, b)
      c = a.nil? ? {} : a.dup

      (b.nil? ? {} : b).each do |k, v|
        if c.include?(k)
          if v.nil?
            # the new value is nil, completely remove the entry
            c.delete(k)
          else
            if v.class == Hash
              # recurse
              c[k] = intelligent_merge(c[k], v)
            else
              # update existing non-nil value
              c[k] = v
            end
          end
        else
          # new value
          c[k] = v
        end
      end

      return c
    end

    def cache_school_integration_data(school_id)
      school_id = school_id.to_i

      # Cached already?
      if INTEGRATIONS_CACHE.include?(school_id)
        return INTEGRATIONS_CACHE[school_id]
      end

      # Add a new school
      entry = {
        # Third-party integrations
        integrations: Set.new([]),
        integration_names: {},
        integrations_by_type: {},

        # Password requirements set by a third-party system
        password_requirements: nil,
      }

      data = Puavo::Organisation.find(LdapOrganisation.current.cn).value_by_key('integrations')
      data = {} unless data

      global = data['global'] || {}
      school = data[school_id] || {}

      # List of external integration names. These names must match to the list
      # defined in integration definitions.
      integration_definitions = Puavo::CONFIG.fetch('integration_definitions', {})

      definition_names = Set.new(integration_definitions.keys)
      for_this_school = Set.new(school['integrations'] || global['integrations'] || [])

      by_type = {}

      (definition_names & for_this_school).each do |name|
        definition = integration_definitions[name]

        next if definition.nil? || definition.empty?
        next unless definition.include?('name')
        next unless definition.include?('type')

        entry[:integrations] << name
        entry[:integration_names][name] = definition['name']

        # Sort integrations by their type, as they're displayed by type
        type = definition['type']
        by_type[type] = [] unless by_type.include?(type)
        by_type[type] << definition['name']
      end

      # Then sort the contents of each integration type
      by_type.each { |k, v| v.sort! }

      entry[:integrations].freeze
      entry[:integration_names].freeze
      entry[:integrations_by_type] = by_type.freeze

      # Password requirements
      requirements = school['password_requirements'] || global['password_requirements'] || ''
      requirements = nil if requirements == ''
      entry[:password_requirements] = requirements.freeze

      entry.freeze
      INTEGRATIONS_CACHE[school_id] = entry
      return entry
    end

    # These methods cannot be put in the School object, because then we could not query
    # global settings in password forms (we don't have school objects in those).

    # Retrieves a set of third-party integration names for the school identified by its puavoId
    def get_school_integrations(school_id)
      return cache_school_integration_data(school_id)[:integrations]
    end

    def get_school_integration_names(school_id)
      return cache_school_integration_data(school_id)[:integration_names]
    end

    def get_school_integrations_by_type(school_id)
      return cache_school_integration_data(school_id)[:integrations_by_type]
    end

    # 'integration_type' is a string that contains a word like "primus" or "gsuite"
    def school_has_integration?(school_id, integration_name)
      return cache_school_integration_data(school_id)[:integrations].include?(integration_name)
    end

    # Password requirements for this school
    def get_school_password_requirements(school_id)
      return cache_school_integration_data(school_id)[:password_requirements]
    end
  end
end
