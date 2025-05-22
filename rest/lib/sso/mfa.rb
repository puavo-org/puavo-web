# Multi-factor authentication

module MFA
  def _mfa_redis
    Redis::Namespace.new('mfa_sso_login', redis: REDIS_CONNECTION)
  end

  # Shows the initial MFA code request form
  def mfa_ask_code
    request_id = make_request_id

    session_key, session_data = mfa_read_session(request_id)
    request_id = session_data['request_id']   # resume logging

    rlog.info("[#{request_id}] displaying the MFA login form for session \"#{session_key}\"")

    @token = session_key
    mfa_show_form
  end

  # Processes the MFA form submission. Checks the MFA code and either throws the browser
  # back to the form, or continues the login process.
  def mfa_check_code
    request_id = make_request_id
    session_key = nil
    user_uuid = nil

    begin
      session_key, session_data = mfa_read_session(request_id)
      request_id = session_data['request_id']   # resume logging
      user_uuid = session_data['user_uuid']

      rlog.info("[#{request_id}] processing the MFA login form for session \"#{session_key}\"")

      if params.include?('cancel')
        # Cancel the MFA login, return to the original login form
        rlog.info("[#{request_id}] canceling the login (#{session_data['original_url']})")

        mfa_destroy_session(session_key, user_uuid)
        return redirect session_data['original_url']
      end

      # Is the code valid? Only the MFA verification server knows that, so ask it.
      mfa_code = params.fetch('mfa_code', nil)

      rlog.info("[#{request_id}] sending the code check request to \"#{CONFIG['mfa_server']['server']}\"")

      response = HTTP
        .auth("Bearer #{CONFIG['mfa_server']['bearer_key']}")
        .headers('X-Request-ID' => request_id)
        .post("#{CONFIG['mfa_server']['server']}/v1/authenticate", json: {
          userid: user_uuid,
          code: mfa_code
        })

      rlog.info("[#{request_id}] MFA server response ID: #{response.headers['X-Request-ID']}")

      response_data = JSON.parse(response.body.to_s)

      if response.status == 403 && response_data['status'] == 'fail' && response_data['messages'].include?('2002')
        # It wasn't
        rlog.info("[#{request_id}] the code is not valid")

        if _mfa_redis.incr(user_uuid) > 4
          # We've exceeded the attempt counter
          mfa_destroy_session(session_key, user_uuid)
          generic_error(t.mfa.too_many_attempts)
        end

        @token = session_key
        @mfa_error = t.mfa.incorrect_code
        mfa_show_form
      elsif response.status == 200 && response_data['status'] == 'success' && response_data['messages'].include?('1002')
        # It was. Continue the original login. Also handle SSO sessions while we're at it.
        rlog.info("[#{request_id}] the code is valid, continuing")

        mfa_destroy_session(session_key, user_uuid)

        if session_data['type'] == 'jwt'
          session_create(
            request_id,
            session_data['sso_session']['organisation'],
            session_data['sso_session']['service_domain'],
            session_data['sso_session']['service_dn'],
            session_data['sso_session']['user_dn'],
            session_data['user_hash'],
            session_data['sso_session']['had_session']
          )

          return do_service_redirect(request_id, session_data['user_hash'], session_data['redirect_url'])
        end
      else
        rlog.info("[#{request_id}] MFA server backend error:")
        rlog.info("[#{request_id}]   #{response.inspect}")
        rlog.info("[#{request_id}]   #{response_data.inspect}")

        mfa_destroy_session(session_key, user_uuid)
        generic_error(t.mfa.validation_server_error(request_id))
      end
    rescue StandardError => e
      rlog.info("[#{request_id}] unhandled MFA form processing exception: #{e}")

      if session_key || user_uuid
        rlog.info("[#{request_id}] clearing MFA session data")
        mfa_destroy_session(session_key, user_uuid)
      end

      generic_error(t.mfa.system_error(request_id))
    end
  end

  def mfa_show_form
    # The MFA form uses the same base layout as the normal login form, so this must be set.
    # The form cannot be customised yet, but that's not important right now.
    @login_content = {
      'prefix' => '/v3/login',
      'mfa_post_uri' => '/v3/mfa',

      'mfa_help' => t.mfa.help,
      'mfa_help2' => t.mfa.help2,
      'mfa_continue' => t.mfa.continue,
      'mfa_cancel' => t.mfa.cancel,
    }

    halt 401, common_headers(), erb(:mfa_form, :layout => :layout)
  end

  def mfa_create_session(key, uuid, data)
    # Store the data for PUAVO_MFA_LOGIN_TIME seconds. If the user does not enter their MFA code
    # within that time, the login process is invalidated.
    redis = _mfa_redis

    # I don't know how reliable Redis' transactions really are
    redis.multi do |m|
      m.set(key, data.to_json.to_s, nx: true, ex: PUAVO_MFA_LOGIN_TIME)
      m.set(uuid, '0', nx: true, ex: PUAVO_MFA_LOGIN_TIME)
    end
  end

  def mfa_read_session(request_id)
    key = params.fetch('token', nil)
    data = key.nil? ? nil : _mfa_redis.get(key)

    unless data
      rlog.error("[#{request_id}] MFA session token \"#{key}\" does not identify any active MFA login session in Redis")
      generic_error(t.mfa.token_expired)
      # generic_error() halts, so no return value
    end

    [key, JSON.parse(data)]
  rescue StandardError => e
    rlog.error("[#{request_id}] unable to load MFA session data from Redis: #{e}")
    generic_error(t.mfa.system_error(request_id))
    # generic_error() halts, so no return value
  end

  def mfa_destroy_session(key, uuid)
    _mfa_redis.del(key)
    _mfa_redis.del(uuid)
  end
end
