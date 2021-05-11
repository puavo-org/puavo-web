# Helper methods for third-party system integrations

require 'json'

if ENV.include?('RAILS_ENV') && ENV['RAILS_ENV'] != 'test'
  # OF COURSE puavo-rest tests will include this file and then explode
  # because puavo-rest's Gemfile does not include the cron parser gem.
  # I can't even begin/rescue the require, as apparently Rails does
  # something that overrides exception handling here.
  require 'parse-cron'
end

module Puavo
  module Integrations
    # Caches integration data. Indexed by school puavoIds and the special "global" identifier.
    INTEGRATIONS_CACHE = {}

    # Known action names for synchronous actions. Actions not listed here
    # are removed at load-time.
    KNOWN_ACTIONS = Set.new(['delete_user', 'change_password']).freeze

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

    # "Nicely" formats the next synchronisation time
    def split_time(seconds)
      value = seconds

      days = (value / 86400).to_i
      value -= days * 86400

      hours = (value / 3600).to_i
      value -= hours * 3600

      minutes = (value / 60).to_i
      value -= minutes * 60

      # omit parts that aren't needed
      parts = []
      parts << sprintf('%d d', days) if days > 0
      parts << sprintf('%d h', hours) if hours > 0
      parts << sprintf('%d m', minutes) if minutes > 0

      if value > 0 && minutes <= 1
        # special case: less than a minute left, improves rounding
        parts << sprintf('%d s', value)
      end

      return '' if parts.empty?
      return "(#{parts.join(', ')})"
    end

    def has_fully_empty_definition?(haystack, needle)
      haystack.include?(needle) && (haystack[needle].nil? || haystack[needle].empty?)
    end

    def cache_school_integration_data(organisation, school_id)
      school_id = school_id.to_i

      # Add a new organisation
      unless INTEGRATIONS_CACHE.include?(organisation)
        INTEGRATIONS_CACHE[organisation] = {}
      end

      # Cached already?
      if INTEGRATIONS_CACHE[organisation].include?(school_id)
        return INTEGRATIONS_CACHE[organisation][school_id]
      end

      # Add a new school
      entry = {
        # Third-party integrations
        integrations: Set.new([]),
        integration_names: {},
        integrations_by_type: {},

        # What actions are updated synchronously and to what systems
        sync_actions: {},

        # Password changing form customisations
        password_form: {
          banner: nil,
          domain: nil
        },

        # Password requirements set by a third-party system
        password_requirements: nil,

        # Schedule for third-party integrations
        schedule: {},
      }

      data = Puavo::Organisation.find(organisation).value_by_key('integrations')
      data = {} unless data

      global = data['global'] || {}
      school = data[school_id] || {}

      # List of external integration names. These names must match to the list
      # defined in integration definitions.
      integration_definitions = Puavo::CONFIG.fetch('integration_definitions', {})

      definition_names = Set.new(integration_definitions.keys)
      for_this_school = Set.new(school['integrations'] || global['integrations'] || [])

      if has_fully_empty_definition?(school, 'integrations')
        # Completely clear all integrations for this school
        for_this_school = Set.new([])
      end

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

      # Password form customisations. These are always defined in the
      # "global" section, but they apply to all schools. Just copy them
      # to every school. Perhaps one day we can do these per-school,
      # if the form can deduct which school the user is in?
      if global.include?('password_form')
        if global['password_form'].include?('banner')
          entry[:password_form][:banner] = global['password_form']['banner']
        end

        if global['password_form'].include?('domain')
          entry[:password_form][:domain] = global['password_form']['domain']
        end
      end

      # Password requirements
      requirements = nil

      if school.include?('password_requirements')
        requirements = school['password_requirements']
      elsif global.include?('password_requirements')
        requirements = global['password_requirements']
      end

      unless requirements.nil?
        # Completely empty value disables password requirements for this school,
        # overriding global values (if any)
        requrements = nil if requirements.empty?
      end

      entry[:password_requirements] = requirements.freeze

      # Actions that causes *synchronous* updates to some external URL/system. If
      # a synchronous update fails, the entire action is aborted.
      sync_global = global['sync_actions'] || {}
      sync_school = school['sync_actions'] || {}

      # Permit per-school configurations remove/undefine global actions
      cleaned_actions = {}

      intelligent_merge(sync_global, sync_school).each do |k, v|
        next unless KNOWN_ACTIONS.include?(k)   # remove unknown actions
        next if v.nil? || v.empty?              # completely remove emptied-out sections
        cleaned_actions[k.to_sym] = v
      end

      if has_fully_empty_definition?(school, 'sync_actions')
        # Completely remove all synchronous actions for this school
        cleaned_actions = {}
      end

      entry[:sync_actions] = cleaned_actions.freeze

      # Synchronisation schedules
      schedule = {}

      intelligent_merge(global['schedule'], school['schedule']).each do |name, sched|
        # CronParser will throw exceptions if the line isn't valid...
        # but don't catch them. Let it explode.
        schedule[name] = CronParser.new(sched)
      end

      entry[:schedule] = schedule.freeze

      entry.freeze
      INTEGRATIONS_CACHE[organisation][school_id] = entry
      return entry
    end

    # These methods cannot be put in the School object, because then we could not query
    # global settings in password forms (we don't have school objects in those).

    # Get the password changing form customisations
    def get_school_password_form_customisations(organisation, school_id)
      return cache_school_integration_data(organisation, school_id)[:password_form]
    end

    # Retrieves a set of third-party integration names for the school identified by its puavoId
    def get_school_integrations(organisation, school_id)
      return cache_school_integration_data(organisation, school_id)[:integrations]
    end

    def get_school_integration_names(organisation, school_id)
      return cache_school_integration_data(organisation, school_id)[:integration_names]
    end

    def get_school_integrations_by_type(organisation, school_id)
      return cache_school_integration_data(organisation, school_id)[:integrations_by_type]
    end

    # 'integration_type' is a string that contains a word like "primus" or "gsuite"
    def school_has_integration?(organisation, school_id, integration_name)
      return cache_school_integration_data(organisation, school_id)[:integrations].include?(integration_name)
    end

    # Password requirements for this school
    def get_school_password_requirements(organisation, school_id)
      return cache_school_integration_data(organisation, school_id)[:password_requirements]
    end

    # Actions for synchronous updates. Supported actions are listed in KNOWN_ACTIONS.
    def school_has_sync_actions_for?(organisation, school_id, action_name)
      return cache_school_integration_data(organisation, school_id)[:sync_actions].include?(action_name)
    end

    # Get a list of synchronous actions for the school. Optional filtering is done is action_name
    # is not nil.
    def get_school_sync_actions(organisation, school_id, action_name=nil)
      actions = cache_school_integration_data(organisation, school_id)[:sync_actions]

      if action_name
        return actions[action_name]
      else
        return actions
      end
    end

    # Returns a list of external systems where user deletions are synchronised to
    def list_school_synchronised_deletion_systems(organisation, school_id)
      names = get_school_integration_names(organisation, school_id)
      deletions = Set.new

      get_school_sync_actions(organisation, school_id, :delete_user)&.each do |name, _|
        if names.include?(name)
          deletions << names[name]
        end
      end

      return deletions
    end

    # Off-line synchronisation schedules
    def get_school_single_integration_next_update(organisation, school_id, integration_name, now)
      schedule = cache_school_integration_data(organisation, school_id)[:schedule]

      if schedule.include?(integration_name)
        sched = schedule[integration_name]

        return sched.next(now)
      else
        return nil
      end
    end

    def get_school_integration_next_updates(organisation, school_id, now)
      schedule = cache_school_integration_data(organisation, school_id)[:schedule]

      out = {}

      schedule.each do |name, s|
        next_at = s.next(now)
        diff = -(now - next_at).to_i    # negative times are not fun

        out[name] = {
          at: next_at,
          in: split_time(diff)
        }
      end

      return out
    end

    # ----------------------------------------------------------------------------------------------
    # ----------------------------------------------------------------------------------------------

    # These are the messages the synchronisation server sends back to us,
    # explaining why the operation failed (or succeeded). Any response that
    # isn't listed here is rejected, so this is a whitelist.
    SYSTEM_REPLY_CODES = Set.new([
      'ok',
      'unknown_version',
      'unknown_system',
      'unknown_operation',
      'configuration_error',
      'bad_request',
      'unauthorized',
      'bad_credentials',
      'remote_server_did_not_respond',
      'remote_server_refused',
      'incomplete_request',
      'malformed_reply',
      'server_error',
      'rate_limit',
      'network_error',
      'unknown_error',
    ]).freeze

    # These replies are operation/system specific and not necessarily fatal. Each
    # must be handled case-by-case basis to figure out if it's actually an error.
    OPERATION_REPLY_CODES = Set.new([
      'invalid_username',
      'user_not_found',
    ]).freeze

    # The 'msg' is a code listed in the above set. It will be translated and displayed
    # to the user.
    class OperationError < StandardError
      def initialize(msg)
        super
      end
    end

    # Returns a hash of { success, code, message } if the operation succeds; throws
    # exceptions for anything else
    def do_operation(request_id, url, operation, system, parameters)
      # --------------------------------------------------------------------------------------------
      # Send

      req_data = {
        version: 0,
        operation: operation.to_s,
        system: system,
        request_id: request_id,
        request_timestamp: Time.now.to_f,
      }

      if parameters
        req_data[:parameters] = parameters
      end

      uri = URI.parse(url)
      http = Net::HTTP.new(uri.host, uri.port)
      request = Net::HTTP::Post.new(uri.request_uri)
      request.body = req_data.to_json

      logger.info("[#{request_id}] Sending network request")

      response = http.request(request)

      logger.info("[#{request_id}] Network request complete")

      # --------------------------------------------------------------------------------------------
      # Process the response

      now = Time.now.to_f
      code = response.code.to_i
      body = response.body

      logger.info("[#{request_id}] Raw response code: \"#{code}\"")
      logger.info("[#{request_id}] Raw response body: \"#{body}\"")

      if code == 400
        raise OperationError, 'bad_request'
      end

      if code == 401 || code == 403
        raise OperationError, 'unauthorized'
      end

      if code == 404
        # it's almost certain that the URL in organisations.yml is incorrect
        raise OperationError, "configuration_error"
      end

      if code == 500
        raise OperationError, 'server_error'
      end

      reply_data = JSON.parse(body)

      unless reply_data.include?('version') && reply_data.include?('operation') &&
             reply_data.include?('system') && reply_data.include?('reply_id') &&
             reply_data.include?('reply_timestamp') && reply_data.include?('request_id') &&
             reply_data.include?('request_timestamp') && reply_data.include?('success') &&
             reply_data.include?('code')
        logger.error("[#{request_id}] Incomplete reply, not all required fields are present")
        raise OperationError, 'malformed_reply'
      end

      logger.info("[#{request_id}] Received a reply with ID \"#{reply_data['reply_id']}\"")
      logger.info("[#{request_id}] Request roundtrip time: #{now - reply_data['request_timestamp']} seconds")

      if reply_data['request_id'] != request_id
        logger.error("[#{request_id}] Reply request ID (#{reply_data['request_id']}) is not the one we sent!")
        raise OperationError, 'malformed_reply'
      end

      if reply_data['version'] != 0
        logger.error("[#{request_id}] Invalid reply version (#{reply_data['version']})")
        raise OperationError, 'unknown_version'
      end

      # TODO: Should we also verify "operation" and "system"?

      # Process the reply code. These are common and shared between all requests.
      # There are some operation-specific codes that we don't handle here.
      code = reply_data['code']

      unless SYSTEM_REPLY_CODES.include?(code) || OPERATION_REPLY_CODES.include?(code)
        logger.error("[#{request_id}] Unknown reply code \"#{code}\"")
        raise OperationError, 'malformed_reply'
      end

      if reply_data['success'] == true
        # The call was a success. Assume 'code' is 'ok'.
        return {
          success: true,
          code: code,
          message: reply_data['message'] || nil,
        }
      end

      if OPERATION_REPLY_CODES.include?(code)
        # Let the caller deal with operation/system -specific errors
        return {
          success: false,
          code: code,
          message: reply_data['message'] || nil,
        }
      end

      # It's a common error we can handle
      raise OperationError, code
    end

    # Creates a unique ID for a synchronous call, for logging purposes
    def generate_synchronous_call_id
      'ABCDEGIJKLMOQRUWXYZ12346789'.split('').sample(10).join
    end

    def google_delete_user(request_id, params, args)
      # verify our parameters
      unless params.include?('url')
        logger.info("[#{request_id}] google_delete_user(): missing server URL in 'params'")
        raise OperationError, 'configuration_error'
      end

      unless args.include?(:organisation) && args.include?(:user) && args.include?(:school)
        logger.info("[#{request_id}] google_delete_user(): missing required arguments")
        raise OperationError, 'configuration_error'
      end

      url = params['url']

      logger.info("[#{request_id}] google_delete_user(): sending a deletion request to \"#{url}\"")

      response = do_operation(request_id, url, :delete_user, 'google', {
        organisation: args[:organisation],
        user: args[:user].uid,
        user_id: args[:user].id.to_i,
        school: args[:school].cn,
        school_id: args[:school].id.to_i,
      })

      if response[:success] == true
        return true, nil
      end

      if response[:code] == 'user_not_found'
        # whatever
        logger.info("[#{request_id}] google_delete_user(): the user does not exist, ignoring")
        return true, nil
      end

      return false, response[:code]
    end

    def azure_delete_user(request_id, params, args)
      # verify our parameters
      unless params.include?('url')
        logger.info("[#{request_id}] azure_delete_user(): missing server URL in 'params'")
        raise OperationError, 'configuration_error'
      end

      unless args.include?(:organisation) && args.include?(:user) && args.include?(:school)
        logger.info("[#{request_id}] azure_delete_user(): missing required arguments")
        raise OperationError, 'configuration_error'
      end

      url = params['url']

      logger.info("[#{request_id}] azure_delete_user(): sending a deletion request to \"#{url}\"")

      response = do_operation(request_id, url, :delete_user, 'azure', {
        organisation: args[:organisation],
        user: args[:user].uid,
        user_id: args[:user].id.to_i,
        school: args[:school].cn,
        school_id: args[:school].id.to_i,
      })

      if response[:success] == true
        return true, nil
      end

      if response[:code] == 'user_not_found'
        # whatever
        logger.info("[#{request_id}] azure_delete_user(): the user does not exist, ignoring")
        return true, nil
      end

      return false, response[:code]
    end

    # Known actions in known systems and the functions that implement them
    SYNCHRONOUS_ACTIONS = {
      :delete_user => {
        'gsuite' => :google_delete_user,
        'azure' => :azure_delete_user,
      },
    }.freeze

    # Runs the specifid synchronous action in the specified system, with the given parameters
    # and arguments. Parameters are defined in organisations.yml, but arguments are different
    # for each action, some actions might not need them at all. Does common exception handling,
    # converting everything to true/false status codes with error message codes.

    # Returns a tuple of [success, error code]; success is false if something went wrong and
    # the error code is a text ID you have to convert to plain text before it can be shown
    # to the user.
    def do_synchronous_action(action, system, request_id, params, **args)
      unless SYNCHRONOUS_ACTIONS.include?(action)
        raise "Puavo::Integrations::do_synchronous_action(): action \"#{action}\" has not " \
              "been defined at all"
      end

      unless SYNCHRONOUS_ACTIONS[action].include?(system)
        raise "Puavo::Integrations::do_synchronous_action(): no system \"#{system}\" defined " \
              "for action \"#{action}\""
      end

      logger.info("do_synchronous_action(): starting request #{request_id}")

      begin
        status, message = send(SYNCHRONOUS_ACTIONS[action][system], request_id, params, args)
        return status, message
      rescue Errno::ECONNREFUSED => e
        logger.error("[#{request_id}] Caught ECONNREFUSED: #{e}")
        return false, 'network_error'
      rescue OperationError => e
        logger.error("[#{request_id}] Caught OperationError: #{e}")
        return false, e.to_s
      rescue StandardError => e
        logger.error("[#{request_id}] Caught StandardError: #{e}")
        return false, 'unknown_error'
      end

      # Should not get here
      raise "WE SHOULD NOT GET HERE. THIS IS A FATAL ERROR. " \
            "Please contact Opinsys support and give them this request ID: #{request_id}."
    end
  end
end
