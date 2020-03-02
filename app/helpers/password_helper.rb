module PasswordHelper
  # Renders the Javascript template at the bottom of the page that sets up
  # password field validation.
  def setup_password_validator(school_id,
                               password_id='user_new_password',
                               confirm_id='user_new_password_confirmation')

    requirements = get_school_password_requirements(school_id)
    logger.info "setup_password_validator(): requirements for school #{school_id} are \"#{requirements}\""
    return unless requirements

    # defaults
    template = 'password/password_length_only'

    locals = {
      password_id: password_id,
      confirm_id: confirm_id,

      # Translate strings and pass them to the Javascript code. ERB templates
      # can be used with Javascript, but it's hairy, apparently uses different
      # rules and is primarily meant for AJAX calls. Also some of these strings
      # are dynamic. I wasted four hours trying to come up with a better
      # solution, but none of them worked. :-( I hate this kind of code.
      strings: {
        ok: t('password.validator_ok'),
        ascii_only: t('password.validator_ascii_only'),
        no_whitespace: t('password.validator_no_whitespace'),
        too_short: t('password.validator_too_short'),
        too_short_with_count: t('password.validator_too_short_with_count'),
        passwords_match: t('password.validator_passwords_match'),
        passwords_dont_match: t('password.validator_passwords_dont_match'),
      }
    }

    case requirements
      when 'Google'
        template = 'password/password_gsuite'

      # TODO: Create a more flexible system for specifying password requirements
      when 'oulu_ad'
        locals[:min_length] = 8
        template = 'password/password_oulu_ad'

      when 'SixCharsMin'
        locals[:min_length] = 6

      when 'SevenCharsMin'
        locals[:min_length] = 7
    else
      logger.warn "setup_password_validator(): unknown requirements \"#{requirements}\", validator template not rendered"
      return
    end

    render partial: template, locals: locals
  end

  # Creates the small help text that explains the password requirements for this organisation/school
  def show_password_requirements(school_id)
    requirements = get_school_password_requirements(school_id)
    return unless requirements

    msg = ''

    case requirements
      when 'Google'
        msg = t('password.gsuite_integration_enabled')

      when 'oulu_ad'
        # this... this is not the proper way of doing it
        msg = t('password.oulu_ad_integration_enabled')

      when 'SixCharsMin'
        msg = t('password.six_chars_min')

      when 'SevenCharsMin'
        msg = t('password.seven_chars_min')

    else
      return
    end

    "<p class=\"passwordNotice\">#{msg}</p>".html_safe
  end
end
