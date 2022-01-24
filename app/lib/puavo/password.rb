# Password helpers

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
                match = (length == rule[:value])
              when '!='
                match = (length != rule[:value])
              when '<'
                match = (length < rule[:value])
              when '<='
                match = (length <= rule[:value])
              when '>'
                match = (length > rule[:value])
              when '>='
                match = (length >= rule[:value])
            end

          when 'regexp'
            match = (rule[:value].match(password) ? '=' : '!=') == rule[:operator]
        end

        errors << rule[:message_id] unless match
      end

      return errors
    end
  end
end
