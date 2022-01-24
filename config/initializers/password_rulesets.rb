# Load and validate the password validation rulesets
# If there are errors in the rules, initialization is aborted because these MUST be correct!

def parse_password_validation_rulesets(data)
  known_rule_types = ['length', 'previous', 'regexp'].freeze
  known_operators = ['=', '!=', '<', '<=', '>', '>='].freeze

  descriptions = {}
  rulesets = {}

  Array(data.fetch('password_rulesets', [])).each do |rs|
    unless rs.include?('id')
      abort "ERROR: Password ruleset is missing an \"id\" parameter"
    end

    if rulesets.include?(rs['id'])
      abort "WARNING: Duplicate password ruleset with ID \"#{rs['id']}\""
    end

    id = rs['id']
    rules = []

    descriptions = rs.fetch('descriptions', {})

    Array(rs.fetch('rules', [])).each do |rule|
      # Validate the rule parameters
      type = rule.fetch('type', nil)

      unless known_rule_types.include?(rule['type'])
        abort "ERROR: Invalid password rule type #{type.inspect} in ruleset \"#{id}\""
      end

      operator = rule.fetch('operator', nil)

      unless known_operators.include?(rule['operator'])
        abort "ERROR: Invalid password rule operator #{operator.inspect} in ruleset \"#{id}\""
      end

      unless rule.include?('value')
        abort "ERROR: Password rule without a value in ruleset \"#{id}\""
      end

      value = rule.fetch('value', nil)
      raw_value = value

      message_id = rule.fetch('message_id', nil)

      unless message_id.class == String && !message_id.empty?
        abort "ERROR: Invalid or missing password rule \"message_id\" parameter in ruleset \"#{id}\""
      end

      # Perform further type-specific validation
      case type
        when 'length'
          if value.class != Integer
            abort "ERROR: Password ruleset \"#{id}\" has a length rule without a valid \"value\" parameter"
          end

          if value < 0
            abort "ERROR: Password ruleset \"#{id}\" has a length rule with a negative length"
          end

        when 'previous'
          if value.class != Integer
            abort "ERROR: Password ruleset \"#{id}\" has a previous rule without a valid \"value\" parameter"
          end

          if value < 0
            abort "ERROR: Password ruleset \"#{id}\" has a previous rule with a negative length"
          end

        when 'regexp'
          unless ['=', '!='].include?(operator)
            abort "ERROR: Operator \"#{operator}\" is not valid for a regexp rule, password ruleset \"#{id}\""
          end

          # Is the regexp valid?
          begin
            value = Regexp.new(value)
          rescue => e
            puts "ERROR: Invalid regexp in password ruleset \"#{id}\":"
            puts "ERROR: #{e}"
            abort
          end
      end

      rules << {
        type: type,
        operator: operator,
        value: value,
        raw_value: raw_value,     # used when converting the rules to JSON for the JavaScript validator
        message_id: message_id,
      }
    end

    rulesets[id] = {
      descriptions: descriptions,
      rules: rules,
    }
  end

  rulesets
end

Puavo::PASSWORD_RULESETS =
  parse_password_validation_rulesets(YAML.load_file("#{Rails.root}/config/puavo_web.yml"))
