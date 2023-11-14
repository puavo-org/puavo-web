# Helper methods for third-party system integrations

# This is a highly-condensed version of the same file in puavo-web.

require 'json'
require 'set'

module Puavo
  module Integrations
    # Caches integration data. Indexed by school puavoIds and the special "global" identifier.
    INTEGRATIONS_CACHE = {}

    # Known action names for synchronous actions. Actions not listed here
    # are removed at load-time.
    KNOWN_ACTIONS = Set.new(['change_password']).freeze

    # "Intelligently" merges two hashes. Hash 'b' can remove entries from 'a'
    # by setting the new value to nil. Nested hashes are handled recursively.
    def self.intelligent_merge(a, b)
      c = a.nil? ? {} : a.dup

      (b.nil? ? {} : b).each do |k, v|
        if c.include?(k)
          if v.nil?
            # the new value is nil, completely remove the entry
            c.delete(k)
          else
            if v.class == Hash
              # recurse
              c[k] = self.intelligent_merge(c[k], v)
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

    def self.has_fully_empty_definition?(haystack, needle)
      haystack.include?(needle) && (haystack[needle].nil? || haystack[needle].empty?)
    end

    def self.cache_school_integration_data(organisation, school_id)
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
        # What actions are updated synchronously and to what systems
        sync_actions: {},
      }

      data = ORGANISATIONS.fetch(organisation, {}).fetch('integrations', {})
      data = {} unless data

      global = data['global'] || {}
      school = data[school_id] || {}

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

      entry.freeze
      INTEGRATIONS_CACHE[organisation][school_id] = entry
      return entry
    end

    # Get a list of synchronous actions for the school. Optional filtering is done is action_name
    # is not nil.
    def self.get_school_sync_actions(organisation, school_id, action_name=nil)
      actions = self.cache_school_integration_data(organisation, school_id)[:sync_actions]

      if action_name
        return actions[action_name]
      else
        return actions
      end
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
      'unmet_password_requirements',
      'reused_password',
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
    def self.do_operation(request_id, url, operation, system, parameters)
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
      http.open_timeout = 5
      request = Net::HTTP::Post.new(uri.request_uri)
      request.body = req_data.to_json

      $rest_log.info("[#{request_id}] do_operation(): sending network request")

      response = http.request(request)

      $rest_log.info("[#{request_id}] do_operation(): network request complete")

      # --------------------------------------------------------------------------------------------
      # Process the response

      now = Time.now.to_f
      code = response.code.to_i
      body = response.body

      $rest_log.info("[#{request_id}]   Raw response code: \"#{code}\"")
      $rest_log.info("[#{request_id}]   Raw response body: \"#{body}\"")

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
        $rest_log.error("[#{request_id}] Incomplete reply, not all required fields are present")
        raise OperationError, 'malformed_reply'
      end

      $rest_log.info("[#{request_id}] Received a reply with ID \"#{reply_data['reply_id']}\"")
      $rest_log.info("[#{request_id}] Request roundtrip time: #{now - reply_data['request_timestamp']} seconds")

      if reply_data['request_id'] != request_id
        $rest_log.error("[#{request_id}] Reply request ID (#{reply_data['request_id']}) is not the one we sent!")
        raise OperationError, 'malformed_reply'
      end

      if reply_data['version'] != 0
        $rest_log.error("[#{request_id}] Invalid reply version (#{reply_data['version']})")
        raise OperationError, 'unknown_version'
      end

      # TODO: Should we also verify "operation" and "system"?

      # Process the reply code. These are common and shared between all requests.
      # There are some operation-specific codes that we don't handle here.
      code = reply_data['code']

      unless SYSTEM_REPLY_CODES.include?(code) || OPERATION_REPLY_CODES.include?(code)
        $rest_log.error("[#{request_id}] Unknown reply code \"#{code}\"")
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
    def self.generate_synchronous_call_id
      'ABCDEGIJKLMOQRUWXYZ12346789'.split('').sample(10).join
    end

    def self.azure_change_password(request_id, params, args)
      # verify our parameters
      unless params.include?('url')
        $rest_log.error("[#{request_id}] azure_change_password(): missing server URL in 'params'")
        raise OperationError, 'configuration_error'
      end

      unless args.include?(:organisation) && args.include?(:user) && args.include?(:new_password)
        $rest_log.error("[#{request_id}] azure_change_password(): missing required arguments")
        raise OperationError, 'configuration_error'
      end

      url = params['url']

      $rest_log.info("[#{request_id}] azure_change_password(): sending a request to \"#{url}\"")

      response = do_operation(request_id, url, :change_password, 'azure', {
        organisation: args[:organisation],
        user: args[:user].username,
        user_id: args[:user].id.to_i,
        new_password: args[:new_password],
      })

      if response[:success] == true
        return true, nil
      end

      if response[:code] == 'user_not_found'
        # whatever
        $rest_log.info("[#{request_id}] azure_change_password(): ignoring a missing user, assuming everything is OK")
        return true, nil
      end

      return false, response[:code]
    end

    def self.google_change_password(request_id, params, args)
      # verify our parameters
      unless params.include?('url')
        $rest_log.error("[#{request_id}] google_change_password(): missing server URL in 'params'")
        raise OperationError, 'configuration_error'
      end

      unless args.include?(:organisation) && args.include?(:user) && args.include?(:new_password)
        $rest_log.error("[#{request_id}] google_change_password(): missing required arguments")
        raise OperationError, 'configuration_error'
      end

      url = params['url']

      $rest_log.info("[#{request_id}] google_change_password(): sending a request to \"#{url}\"")

      response = do_operation(request_id, url, :change_password, 'google', {
        organisation: args[:organisation],
        user: args[:user].username,
        user_id: args[:user].id.to_i,
        new_password: args[:new_password],
      })

      if response[:success] == true
        return true, nil
      end

      if response[:code] == 'user_not_found'
        # whatever
        $rest_log.info("[#{request_id}] google_change_password(): ignoring a missing user, assuming everything is OK")
        return true, nil
      end

      return false, response[:code]
    end

    # Known actions in known systems and the functions that implement them
    SYNCHRONOUS_ACTIONS = {
      :change_password => {
        'azure' => :azure_change_password,
        'gsuite' => :google_change_password,
      },
    }.freeze

    # Runs the specifid synchronous action in the specified system, with the given parameters
    # and arguments. Parameters are defined in organisations.yml, but arguments are different
    # for each action, some actions might not need them at all. Does common exception handling,
    # converting everything to true/false status codes with error message codes.

    # Returns a tuple of [success, error code]; success is false if something went wrong and
    # the error code is a text ID you have to convert to plain text before it can be shown
    # to the user.
    def self.do_synchronous_action(action, system, request_id, params, **args)
      unless SYNCHRONOUS_ACTIONS.include?(action)
        $rest_log.error(
          "[#{request_id}] do_synchronous_action(): action \"#{action}\" has not " \
          "been defined at all"
        )

        return false, 'configuration_error'
      end

      unless SYNCHRONOUS_ACTIONS[action].include?(system)
        $rest_log.error(
          "[#{request_id}] do_synchronous_action(): no system \"#{system}\" defined " \
          "for action \"#{action}\""
        )

        return false, 'configuration_error'
      end

      $rest_log.info("[#{request_id}] do_synchronous_action(): starting action")

      begin
        status, message = send(SYNCHRONOUS_ACTIONS[action][system], request_id, params, args)
        return status, message
      rescue Errno::ECONNREFUSED => e
        $rest_log.error("[#{request_id}] do_synchronous_action(): caught ECONNREFUSED: #{e}")
        return false, 'network_error'
      rescue OperationError => e
        $rest_log.error("[#{request_id}] do_synchronous_action(): caught OperationError: #{e}")
        return false, e.to_s
      rescue StandardError => e
        $rest_log.error("[#{request_id}] do_synchronous_action(): caught StandardError: #{e}")

        if e.to_s == 'execution expired'
          $rest_log.error("[#{request_id}]   -> this is a network timeout, can't contact the synchronisation server")
          return false, 'network_error'
        end

        return false, 'unknown_error'
      end

      # Should not get here
      raise "SHOULD NOT GET HERE. THIS IS A FATAL ERROR."
    end
  end
end
