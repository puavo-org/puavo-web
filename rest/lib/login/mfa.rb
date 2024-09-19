# Multi-factor authentication form and code validation

require_relative './utility'

module PuavoLoginMFA
  def _mfa_redis
    Redis::Namespace.new('sso:mfa', redis: REDIS_CONNECTION)
  end

  def mfa_initialize(login_key, login_data)
    # This is the MFA attempt counter that gets incremented every time the MFA form
    # is submitted. It is used to limit how many times the code can be entered.
    _mfa_redis.set(login_key, '1', nx: true, ex: PUAVO_MFA_LOGIN_TIME)
  end

  def mfa_clear(login_key)
    # Remove the attempt counter
    _mfa_redis.del(login_key)
  end

  # Shows the initial MFA code request form
  def mfa_ask_code
    # Resume the login session. This explodes loudly if the MFA form is accessed directly by URL.
    login_key = params.fetch('login_key', '')
    login_data = login_get_data(login_key)
    request_id = login_data['request_id']

    mfa_initialize(login_key, login_data)

    rlog.info("[#{request_id}] displaying the MFA login form for login session \"#{login_key}\"")
    mfa_show_form(login_key, was_oidc: login_data['was_oidc'])
  end

  # Shows the MFA code form
  def mfa_show_form(login_key, error_message: nil, halt_code: 200, was_oidc: false)
    # The MFA form uses the same base layout as the normal login form, so this must be set.
    # The form cannot be customised yet, but that's not important right now.
    @login_content = {
      'prefix' => '/v3/login',
      'login_key' => login_key,
      'mfa_post_uri' => was_oidc ? '/oidc/mfa' : '/v3/mfa',
      'error' => error_message,

      'mfa_help' => t.mfa.help,
      'mfa_help2' => t.mfa.help2,
      'mfa_continue' => t.mfa.continue,
      'mfa_cancel' => t.mfa.cancel,
    }

    # This does not have Kerberos, so we can use any normal HTTP code here
    halt halt_code, common_headers(), erb(:mfa_form, layout: :layout)
  end

  # Processes the MFA form submission. Checks the MFA code and either throws the browser
  # back to the form, or continues the login process.
  def mfa_check_code
    # Resume the login session
    login_key = params.fetch('login_key', '')
    login_data = login_get_data(login_key)
    request_id = login_data['request_id']

    begin
      rlog.info("[#{request_id}] processing the MFA form submission for login session \"#{login_key}\"")

      if params.include?('cancel')
        # Cancel the MFA form and return to the original login form
        url = login_data['original_url']

        rlog.info("[#{request_id}] user wants to cancel, returning to \"#{url}\"")
        login_clear_data(login_key)
        mfa_clear(login_key)

        return redirect url
      end

      # Is the code valid? Only the MFA verification server knows that, so ask it.
      mfa_code = params.fetch('mfa_code', nil)

      rlog.info("[#{request_id}] sending the code check request to \"#{CONFIG['mfa_server']['server']}\"")

      response = HTTP
        .auth("Bearer #{CONFIG['mfa_server']['bearer_key']}")
        .headers('X-Request-ID' => request_id)
        .post("#{CONFIG['mfa_server']['server']}/v1/authenticate", json: {
          userid: login_data['user']['uuid'],
          code: mfa_code
        })

      rlog.info("[#{request_id}] MFA server response ID: #{response.headers['X-Request-ID']}")

      response_data = JSON.parse(response.body.to_s)

      if response.status == 403 && response_data['status'] == 'fail' && response_data['messages'].include?('2002')
        # It wasn't
        rlog.info("[#{request_id}] the code is not valid")

        if _mfa_redis.incr(login_key) > 5
          # Too many failed attempts
          rlog.info("[#{request_id}] too many failed MFA attempts")

          login_clear_data(login_key)
          mfa_clear(login_key)

          generic_error(t.mfa.too_many_attempts)
        end

        mfa_show_form(login_key, error_message: t.mfa.incorrect_code, halt_code: 401, was_oidc: login_data['was_oidc'])
      elsif response.status == 200 && response_data['status'] == 'success' && response_data['messages'].include?('1002')
        # It was. Continue to the stage 2 handler.
        rlog.info("[#{request_id}] the code is valid, continuing")

        mfa_clear(login_key)

        return stage2(login_key, login_data)
      else
        # Unknown MFA server error
        rlog.info("[#{request_id}] MFA server backend error:")
        rlog.info("[#{request_id}]   #{response.inspect}")
        rlog.info("[#{request_id}]   #{response_data.inspect}")

        login_clear_data(login_key)
        mfa_clear(login_key)

        generic_error(t.mfa.validation_server_error(request_id))
      end
    rescue StandardError => e
      rlog.info("[#{request_id}] unhandled MFA form processing exception: #{e}")

      login_clear_data(login_key)
      mfa_clear(login_key)

      generic_error(t.mfa.system_error(request_id))
    end
  end
end
