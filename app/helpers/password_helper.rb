module PasswordHelper
  # Renders the Javascript template at the bottom of the page that sets up
  # password field validation.
  def setup_password_validator(organisation_name, school_id, password_field_id, confirm_field_id, callback=nil)
    ruleset_name = get_school_password_requirements(organisation_name, school_id)

    logger.info("setup_password_validator(): password validation ruleset for school #{school_id} " \
                "in organisation \"#{organisation_name}\" is \"#{ruleset_name}\"")

    rules = ruleset_name ? Puavo::PASSWORD_RULESETS[ruleset_name][:rules] : []

    # Always render the validator template, even if there are no rules. If the rule list is empty,
    # then the validator simply ensures the password confirmation matches the password and
    # does nothing else.
    render partial: 'password/password_validator', locals: {
      password_field_id: password_field_id,
      confirm_field_id: confirm_field_id,
      rules: rules,
      callback: callback,
    }
  end

  # Creates the small help text that explains the password requirements for this organisation/school
  def show_password_requirements(organisation_name, school_id)
    ruleset_name = get_school_password_requirements(organisation_name, school_id)
    return unless ruleset_name

    instructions = Puavo::PASSWORD_RULESETS[ruleset_name][:instructions]
    lang = I18n.locale.to_s
    return unless instructions.include?(lang)

    "<p class=\"passwordNotice\">#{instructions[lang]}</p>".html_safe
  end
end
