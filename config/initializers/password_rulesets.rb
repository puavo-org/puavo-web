# Load and validate the password validation rulesets
# If there are errors in the rules, initialization is aborted because these MUST be correct!

def parse_password_validation_rulesets(data)
  known_rule_types = ['length', 'regexp', 'complexity_check'].freeze
  known_operators = ['=', '!=', '<', '<=', '>', '>='].freeze
  types_with_operators = ['length', 'regexp'].freeze

  instructions = {}
  rulesets = {}

  Array(data.fetch('password_rulesets', [])).each do |ruleset|
    unless ruleset.include?('id')
      abort "ERROR: Ruleset is missing an \"id\" parameter, ruleset ignored"
    end

    if rulesets.include?(ruleset['id'])
      abort "WARNING: Ignoring duplicate ruleset with ID \"#{ruleset['id']}\""
    end

    ruleset_id = ruleset['id']
    rules = []
    instructions = ruleset.fetch('instructions', {})

    Array(ruleset.fetch('rules', [])).each do |rule|
      # Validate the common parameters
      type = rule.fetch('type', nil)

      unless known_rule_types.include?(rule['type'])
        abort "ERROR: Invalid rule type #{type.inspect} in ruleset \"#{ruleset_id}\", rule ignored"
      end

      if types_with_operators.include?(type)
        operator = rule.fetch('operator', nil)

        unless known_operators.include?(operator)
          abort "ERROR: Invalid rule operator #{operator.inspect} in ruleset \"#{ruleset_id}\", rule ignored"
        end
      end

      message_id = rule.fetch('message_id', nil)

      unless message_id.class == String && !message_id.empty?
        abort "ERROR: Invalid or missing rule \"message_id\" parameter in ruleset \"#{ruleset_id}\", rule ignored"
      end

      # Perform type-specific checks
      cleaned = {
        type: type,
        message_id: message_id,
      }

      if types_with_operators.include?(type)
        cleaned[:operator] = operator
      end

      case type
        # -------------------------------------------------------------------------------------------
        # Length check

        when 'length'
          unless rule.include?('length')
            abort "ERROR: Length rule without a \"length\" value in ruleset \"#{ruleset_id}\", rule ignored"
          end

          length = rule['length']

          if length.class != Integer
            abort "ERROR: Ruleset \"#{ruleset_id}\" has a length rule without a valid \"length\" parameter, rule ignored"
          end

          if length < 0
            abort "ERROR: Ruleset \"#{ruleset_id}\" has a negative length rule, rule ignored"
          end

          cleaned[:length] = length

        # -------------------------------------------------------------------------------------------
        # Regexp match/mismatch

        when 'regexp'
          unless rule.include?('regexp')
            abort "ERROR: Regexp rule without a \"regexp\" value in ruleset \"#{ruleset_id}\", rule ignored"
          end

          unless ['=', '!='].include?(operator)
            abort "ERROR: Operator \"#{operator}\" is not valid for a regexp rule, ruleset \"#{ruleset_id}\", rule ignored"
          end

          # Is the regexp valid?
          begin
            Regexp.new(rule['regexp'])
          rescue => e
            puts "ERROR: Invalid regexp in ruleset \"#{ruleset_id}\", rule ignored:"
            puts "ERROR: #{e}"
            abort
          end

          cleaned[:regexp] = rule['regexp']

        # -------------------------------------------------------------------------------------------
        # Arbitrary complexity checker

        when 'complexity_check'
          unless rule.include?('min_matches')
            abort "ERROR: Complexity checker rule without a \"min_matches\" value in ruleset \"#{ruleset_id}\", rule ignored"
          end

          min_matches = rule['min_matches']

          if min_matches.class != Integer || min_matches < 1
            abort "ERROR: Ruleset \"#{ruleset_id}\" has a complexity check rule without a valid \"min_matches\" parameter, rule ignored"
          end

          unless rule.include?('regexps')
            abort "ERROR: Missing \"regexps\" section in optional_regexps rule, password ruleset \"#{ruleset_id}\""
          end

          cleaned[:min_matches] = min_matches

          # Are the regexps valid?
          begin
            Array(rule['regexps']).each { |v| Regexp.new(v) }
          rescue => e
            puts "ERROR: Invalid regexp in password ruleset \"#{ruleset_id}\":"
            puts "ERROR: #{e}"
            abort
          end

          cleaned[:regexps] = Array(rule['regexps'])
      end

      rules << cleaned
    end

    rulesets[ruleset_id] = {
      instructions: instructions,
      rules: rules
    }
  end

  rulesets
end

Puavo::PASSWORD_RULESETS =
  parse_password_validation_rulesets(YAML.load_file("#{Rails.root}/config/puavo_web.yml"))
