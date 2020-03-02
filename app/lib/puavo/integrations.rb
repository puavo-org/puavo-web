# Helper methods for third-party system integrations

require 'json'

module Puavo
  module Integrations
    # Caches integration data. Indexed by school puavoIds and the special "global" identifier.
    INTEGRATIONS_CACHE = {}

    # Known action names for synchronous actions. Actions not listed here
    # are removed at load-time.
    KNOWN_ACTIONS = Set.new(['delete_user']).freeze

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

    # Parses a string of hour/minute values (like "2,5-6,22" and so on) into strings
    # containing F ("false") and T ("true") flags indicating which hours or minutes
    # are set. For example, passing ("5-10", 24) will return "FFFFFTTTTTFFFFFFFFFFFFF"
    # and if you look at characters 4 to 9, they'll be "T", indicating they're set.
    # Originally this returned arrays of trues and falses, but strings take up less
    # space and are easier to inspect visually.
    def parse_timestring(s, max_value)
      marks = 'F' * max_value

      # reject anything that isn't a string containing only numbers, commas and/or dashes
      if s.class != String || s =~ /[^0-9\-, ]/
        return marks
      end

      s.split(',').each do |t|
        t.strip!
        next if t.empty?
        next if t[0] == '-' || t[-1] == '-'   # incomplete ranges ("-x" or "x-" or even just "-")

        # is it a single value, or a range?
        parts = t.split('-')

        case parts.count
          # a single value
          when 1
            i = parts[0].to_i(10)
            next if i < 0 || i >= max_value
            marks[i] = 'T'

          # a start-end inclusive range
          when 2
            s = parts[0].to_i(10)
            e = parts[1].to_i(10)
            next if s < 0 || e < 0 || s >= max_value || e >= max_value
            s, e = e, s if s > e    # end > start, swap them
            (s..e).each { |i| marks[i] = 'T' }
        end
      end

      return marks
    end

    # Uses the strings returned by parse_timestring() and figures out when the next
    # synchronisation will take place. 'now' is the start time, usually Time.now,
    # but you can use any moment as a starting point.
    MINUTES_PER_DAY = 60 * 24

    def compute_next_update(hours_lookup, minutes_lookup, now)
      # Each day has 24*60 minutes. Iterate over each minute, starting from *now* and wrapping
      # around at midnight, until we find the next slot where both 'hours_lookup' and
      # 'minutes_lookup' are true, then compute the difference from current time to that time,
      # in minutes. Turn that minute offset into an actual time.
      starting_minute = now.hour * 60 + now.min
      next_in_minutes = nil

      (0..MINUTES_PER_DAY).each do |minute|
        minute_now = (starting_minute + minute) % MINUTES_PER_DAY

        # lookup indexes
        test_h = minute_now / 60
        test_m = minute_now % 60

        if hours_lookup[test_h] == 'T' && minutes_lookup[test_m] == 'T'
          # Found the next one. Compute the offset from 'now' to that moment, in minutes.
          next_in_minutes = minute_now - starting_minute

          if minute_now < starting_minute
            # it happens tomorrow
            next_in_minutes += MINUTES_PER_DAY
          end

          break
        end
      end

      if next_in_minutes.nil?
        # Nothing found. Maybe the time strings are empty, or they did
        # not specify any valid times or time ranges?
        return {
          at: nil,
          in: [-1, -1]
        }
      end

      # A date object representing today at midnight
      now_test = Time.new(now.year, now.month, now.day, now.hour, now.min, 0)

      # Then offset it by the specified amount of minutes. Doesn't matter if it
      # spills past midnight.
      next_update = Time.at(now_test.to_i + next_in_minutes * 60)

      # Hours and minutes *until* the next update
      next_h = next_in_minutes / 60
      next_m = next_in_minutes % 60
      next_h -= 24 if next_h > 23   # tomorrow

      return {
        at: next_update,
        in: [next_h, next_m]
      }
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

        # What actions are updated synchronously and to what systems
        sync_actions: {},

        # Password requirements set by a third-party system
        password_requirements: nil,

        # Schedule for third-party integrations
        schedule: {},
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

      entry[:sync_actions] = cleaned_actions.freeze

      # Synchronisation schedules
      schedule = {}

      #(global['schedule'] || school[]).each do |name, sched|
      intelligent_merge(global['schedule'], school['schedule']).each do |name, sched|
        schedule[name] = {
          hours: parse_timestring(sched['hours'], 24),
          minutes: parse_timestring(sched['minutes'], 60)
        }
      end

      entry[:schedule] = schedule.freeze

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

    # Actions for synchronous updates. Supported actions are listed in KNOWN_ACTIONS.
    def school_has_sync_actions_for?(school_id, action_name)
      return cache_school_integration_data(school_id)[:sync_actions].include?(action_name)
    end

    # Get a list of synchronous actions for the school. Optional filtering is done is action_name
    # is not nil.
    def get_school_sync_actions(school_id, action_name=nil)
      actions = cache_school_integration_data(school_id)[:sync_actions]

      if action_name
        return actions[action_name]
      else
        return actions
      end
    end

    # Off-line synchronisation schedules
    def get_school_single_integration_next_update(school_id, integration_name, now)
      schedule = cache_school_integration_data(school_id)[:schedule]

      if schedule.include?(integration_name)
        sched = schedule[integration_name]

        return compute_next_update(sched[:hours], sched[:minutes], now)
      else
        return nil
      end
    end

    def get_school_integration_next_updates(school_id, now)
      schedule = cache_school_integration_data(school_id)[:schedule]

      out = {}

      schedule.each do |name, s|
        out[name] = compute_next_update(s[:hours], s[:minutes], now)
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
        return true, nil
      end

      return false, response[:code]
    end

    # Known actions in known systems and the functions that implement them
    SYNCHRONOUS_ACTIONS = {
      :delete_user => {
        'gsuite' => :google_delete_user,
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
