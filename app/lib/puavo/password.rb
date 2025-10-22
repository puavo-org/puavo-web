# Password helpers

require 'digest'

module Puavo
  module Password
    # Validate a password against the specified ruleset. The rules have been validated at
    # start-up, so all error checking has been omitted. Returns an array of [status, message],
    # where status is true if the password passed all the checks. If it's false, then 'message'
    # contains a message ID you can use to look up a localised message that can be shown to
    # the user.
    def self.validate_password(password, rules)
      errors = []

      Array(rules || []).each do |rule|
        case rule[:type]
          when 'length'
            length = password.nil? ? 0 : password.length

            case rule[:operator]
              when '='
                match = (length == rule[:length])
              when '!='
                match = (length != rule[:length])
              when '<'
                match = (length < rule[:length])
              when '<='
                match = (length <= rule[:length])
              when '>'
                match = (length > rule[:length])
              when '>='
                match = (length >= rule[:length])
            end

          when 'regexp'
            match = (Regexp.new(rule[:regexp]).match(password) ? '=' : '!=') == rule[:operator]

          when 'complexity_check'
            # Count how many of the regexps match the password
            matches = 0

            rule[:regexps].each { |r| matches += 1 if Regexp.new(r).match(password) }

            match = (matches >= rule[:min_matches])
        end

        errors << rule[:message_id] unless match
      end

      return errors
    end

    def self.password_management_host(path: nil)
      url = URI(Puavo::CONFIG['password_management']['host'])
      url.path = path if path
      url.to_s
    end

    # Sends a password reset email to the requested address. Determines the user automatically.
    def self.send_password_reset_mail(logger, domain, management_host, locale, request_id, address)
      user = User.find(:first, :attribute => "mail", :value => address.strip)

      unless user
        logger.error("[#{request_id}] No user found by that email address")
        return :user_not_found
      end

      logger.info("[#{request_id}] Found user \"#{user.givenName} #{user.sn}\" (\"#{user.uid}\"), " \
                  "ID=#{user.puavoId}, organisation=\"#{domain}\"")

      # grrr, copied from password_controller.rb (method redis_connect)
      db = Redis::Namespace.new('puavo:password_management:send_token', redis: REDIS_CONNECTION)

      if db.get(user.puavoId)
        logger.error("[#{request_id}] This user has already received a password reset link, request rejected")
        return :link_already_sent
      end

      send_token_url = management_host + "/password/send_token"

      tried = false

      begin
        logger.info("[#{request_id}] Generating the reset email, see the password reset host logs at " \
                    "#{management_host} for details")

        rest_response = HTTP.headers(host: domain, 'Accept-Language': locale)
                            .post(send_token_url, params: {
                              # Most of these are just for logging purposes. Abuse cases must
                              # be traceable afterwards.
                              request_id: request_id,
                              id: user.puavoId.to_i,
                              username: user.uid,
                              email: address,
                            })
      rescue => e
        logger.error("[#{request_id}] Request failed: #{e}")

        if e.to_s.include?('Connection reset by peer') && !tried
          logger.info("[#{request_id}] Retrying the request once in 1 second...")
          tried = true
          sleep 1
          retry
        else
          return :link_sending_failed
        end
      end

      if rest_response.status == 200
        unless ENV['RAILS_ENV'] == 'test'
          # The server sends the JWT back as a string
          response_data = JSON.parse(rest_response.body.to_s)

          # Store full user data in Redis. The key is SHA384 of the JWT string. We can't
          # store anything in the public reset link or the JWT itself, because it cannot
          # be decoded on puavo-web without the secret key that only the reset server has.
          # So the "public" JWT only contains some user-identifying data (most of which
          # are public already), but the Redis contains the full information. If the URL
          # is edited, the JWT hash no longer matches and the data cannot be retrieved.
          # This protects effectively against attacks.
          cache_data = {
            id: user.puavoId.to_i,
            uid: user.uid,
            school: user.puavoEduPersonPrimarySchool.to_s.match(/^puavoId=(?<id>\d+),ou=Groups,dc=edu,dc=/)[:id].to_i,
            domain: domain,
          }

          key = Digest::SHA384.hexdigest(response_data['jwt'])

          db.set(user.puavoId, true, :ex => 3600, :nx => true)
          db.set(key, cache_data.to_json, :ex => 3600, :nx => true)

          logger.info("[#{request_id}] Redis entries saved")
        end
      else
        logger.error("[#{request_id}] puavo-rest call failed, response code was: #{rest_response.status}")
        return :puavo_rest_call_failed
      end

      return :ok
    end
  end
end
