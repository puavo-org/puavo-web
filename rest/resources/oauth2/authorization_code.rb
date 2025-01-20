# RFC 6749 section 4.1. Authorization Code Grant
# This implements OpenID Connect for interactive user logins

# Stage 1 --> username+password forms, MFA, Kerberos --> stage 2 --> Stage 3 (token generation)

require 'securerandom'

require_relative './scopes'
require_relative './helpers'
require_relative './access_token'

module PuavoRest
module OAuth2
  # ------------------------------------------------------------------------------------------------
  # Stage 1: Authorization Code Grant
  # This starts an interactive browser-based authorization that uses redirects.

  # RFC 6749 section 4.1.1.
  def oidc_stage1_authorization_request
    request_id = make_request_id

    rlog.info("[#{request_id}] New OpenID Connect authorization request")

    # Until the client ID and redirection URI have been validated, we cannot do error redirects.
    # Instead we display an error message in the browser. This matches RFC 6749 section 3.1.2.4.

    # ----------------------------------------------------------------------------------------------
    # (Re)Load the OpenID Connect configuration file
    # TODO: These must be stored in the database.

    begin
      oidc_config = YAML.safe_load(File.read('/etc/puavo-web/oauth2.yml')).freeze
    rescue StandardError => e
      rlog.error("[#{request_id}] Can't parse the OIDC configuration file: #{e}")

      # Don't reveal the exact reason
      generic_error(t.sso.unspecified_error(request_id))
    end

    # ----------------------------------------------------------------------------------------------
    # Verify the client ID and the target external service

    client_id = params.fetch('client_id', nil)

    rlog.info("[#{request_id}] Client ID: #{client_id.inspect}")

    unless oidc_config['oidc_logins'].include?(client_id)
      rlog.error("[#{request_id}] Unknown/invalid client")
      generic_error(t.sso.invalid_client_id(request_id))
    end

    client_config = oidc_config['oidc_logins'][client_id].freeze

    # Find the target service
    service_dn = client_config['puavo_service']
    rlog.info("[#{request_id}] Target external service DN: #{service_dn.inspect}")

    external_service = get_external_service(service_dn)

    if external_service.nil?
      rlog.error("[#{request_id}] No external service found using that DN")
      generic_error(t.sso.invalid_client_id(request_id))
    end

    rlog.info("[#{request_id}] Target external service name: #{external_service.name.inspect}")

    # ----------------------------------------------------------------------------------------------
    # Verify the redirect URL(s)
    # RFC 6749 section 4.1.1. says this is OPTIONAL, but we require it

    redirect_uri = params['redirect_uri']

    rlog.info("[#{request_id}] Redirect URI: #{redirect_uri.inspect}")

    if client_config.fetch('allowed_redirect_uris', []).find { |uri| uri == redirect_uri }.nil?
      rlog.error("[#{request_id}] The redirect URI is not allowed")
      generic_error(t.sso.invalid_redirect_uri(request_id))
    end

    rlog.info("[#{request_id}] The redirect URI is valid")

    # The client ID and the redirect URI have been validated. We can now do proper error redirects,
    # as specified in RFC 6479 section 4.1.2.1.

    # ----------------------------------------------------------------------------------------------
    # Check the response type. As per RFC 6749 section 4.1.1, this is REQUIRED
    # and its value must be "code".

    response_type = params.fetch('response_type', nil)

    unless response_type == 'code'
      rlog.error("[#{request_id}] Invalid response type #{response_type.inspect} (expected \"code\")")
      return redirect_error(redirect_uri, 400, 'invalid_request', state: params.fetch('state', nil), request_id: request_id)
    end

    # ----------------------------------------------------------------------------------------------
    # Verify the scopes

    scopes = clean_scopes(request_id,
                          params.fetch('scope', ''),
                          BUILTIN_LOGIN_SCOPES,
                          client_config)

    unless scopes[:success]
      return redirect_error(redirect_uri, 400, 'invalid_scope', state: params.fetch('state', nil), request_id: request_id)
    end

    # ----------------------------------------------------------------------------------------------
    # The request is valid. Build a state structure that tracks the process and store it in Redis.

    # This structure tracks the user's OpenID Connect authorization session. While separate
    # from the "login session" that exists during the login form (and the MFA form, if enabled),
    # it is briefly stored inside the login session data when the forms are displayed. It is
    # deleted after the OIDC access token (or the initial JWT) has been generated.
    oidc_state = {
      'request_id' => request_id,
      'client_id' => client_id,
      'redirect_uri' => redirect_uri,
      'scopes' => scopes[:scopes],
      'scopes_changed' => scopes[:changed],     # need to remember this for later responses
      'state' => params.fetch('state', nil),    # the state is merely RECOMMENDED, but not required

      # These will be copied from the login session once it completes (we need to persist these
      # until the initial JWT/access token has been generated)
      'service' => nil,
      'organisation' => nil,
      'user' => nil,
    }

    if params.include?('nonce')
      # The nonce is an optional value used to mitigate replay attacks. It is barely mentioned
      # in RFC 6749, but it is mentioned in the full spec. If specified in the request, we must
      # remember it.
      oidc_state['nonce'] = params['nonce']
    end

    login_key = SecureRandom.hex(64)

    rlog.info("[#{request_id}] Login key: #{login_key.inspect}")

    begin
      # Use the same request ID for everything
      login_data = login_create_data(request_id, external_service, is_trusted: external_service.trusted, next_stage: '/oidc/stage2', was_oidc: true)

      login_data['original_url'] = request.url.to_s

      if request.env.include?('HTTP_USER_AGENT')
        # HACK: "Smuggle" the user agent header across the redirect.
        # Needed for tests, not sure if needed in production.
        login_data['user_agent'] = request.env['HTTP_USER_AGENT']
      end

      # Is there a session for this service?
      session = session_try_login(request_id, external_service)

      if session[:had_session] && session[:redirect]
        # Restore session data
        login_data['had_session'] = true
        login_data['service'] = session[:data]['service']
        login_data['organisation'] = session[:data]['organisation']
        login_data['user'] = session[:data]['user']
      end

      # Will be moved elsewhere once the login completes
      login_data['oidc_state'] = oidc_state

      _login_redis.set(login_key, login_data.to_json, nx: true, ex: PUAVO_LOGIN_TIME)

      if session[:had_session] && session[:redirect]
        # We had a session, skip the form(s)
        return stage2(login_key, login_data)
      end

      # Display the login form (and MFA form if enabled)
      redirect login_data['was_oidc'] ? "/oidc/login?login_key=#{login_key}" : "/v3/sso/login?login_key=#{login_key}"
    rescue StandardError => e
      # WARNING: This resuce block can only handle exceptions that happen *before* the
      # login form is rendered, because the login form renderer halts and never comes
      # back to this method.
      rlog.error("[#{request_id}] Unhandled exception in the SSO system: #{e}")
      rlog.error("[#{request_id}] #{e.backtrace.join("\n")}")
      login_clear_data(login_key)
      generic_error(t.sso.unspecified_error(request_id))
    end

    # Unreachable
  end

  # ------------------------------------------------------------------------------------------------
  # Stage 2: Generate the authorization response (RFC 6749 section 4.1.2.)

  # We get here from the login/MFA form, or directly from stage 1 if an SSO session existed
  # or Kerberos authentication succeeded. In any case, it's a browser redirect.

  def oidc_stage2_authorization_response
    # Get and delete the login data from Redis
    login_key = params.fetch('login_key', '')
    login_data = login_get_data(login_key, delete_immediately: true)
    request_id = login_data['request_id']
    rlog.info("[#{request_id}] OpenID Connect authorization request continues, login key is #{login_key.inspect}")

    # Copy the OpenID Connect session state from the login data
    oidc_state = login_data['oidc_state']

    # Now we know these values
    oidc_state['service'] = login_data['service']
    oidc_state['organisation'] = login_data['organisation']
    oidc_state['user'] = login_data['user']

    # The authentication time is optional, but we can support it easily. It is specified in
    # https://openid.net/specs/openid-connect-core-1_0.html#IDToken.
    oidc_state['auth_time'] = Time.now.utc.to_i

    # Create an SSO session if possible
    session_create(login_key, login_data, {
      'service' => login_data['service'],
      'organisation' => login_data['organisation'],
      'user' => login_data['user'],
    })

    # Generate the session code and stash everything in Redis
    code = SecureRandom.hex(64)
    oidc_redis.set(code, oidc_state.to_json, nx: true, ex: PUAVO_OIDC_LOGIN_TIME)
    rlog.info("[#{request_id}] Generated OIDC session #{code}")

    # Return the parameters to the caller using the redirect URI
    redirect_uri = URI(oidc_state['redirect_uri'])

    query = {
      'iss' => ISSUER,      # RFC 9207
      'code' => code,
      'state' => oidc_state['state']
    }

    if oidc_state['scopes_changed']
      # RFC 6749 section 4.1.2. does not mention this at all, but section 3.3 says
      # the scopes must be included in the response if they are different from the
      # scopes the client specified. The spec is unclear how the scopes should be
      # encoded (array or list). Return them as space-delimited string, because
      # that's how they're originally specified.
      query['scope'] = oidc_state['scopes'].join(' ')
    end

    redirect_uri.query = URI.encode_www_form(query)

    redirect redirect_uri
  end

  # ------------------------------------------------------------------------------------------------
  # Stage 3: Access token request (RFC 6749 section 4.1.3.)

  # Generate ID and access tokens for the client
  def oidc_stage3_access_token_request(temp_request_id)
    # ----------------------------------------------------------------------------------------------
    # Retrive the code and the current state

    begin
      code = params.fetch('code', nil)
      oidc_state = oidc_redis.get(code)
    rescue StandardError => e
      # Don't log the secret (we know it already, but don't log it)
      params['client_secret'] = '[REDACTED]' if params.include?('client_secret')

      rlog.error("[#{temp_request_id}] An attempt to get OIDC state from Redis raised an exception: #{e}")
      rlog.error("[#{temp_request_id}] Request parameters: #{params.inspect}")
      return json_error('server_error', request_id: temp_request_id)
    end

    if oidc_state.nil?
      rlog.error("[#{temp_request_id}] No OpenID Connect state found by code \"#{code}\"")
      return json_error('invalid_request', request_id: temp_request_id)
    end

    # Prevent code reuse, even if we cannot parse the state or an error occurrs
    oidc_redis.del(code)

    begin
      oidc_state = JSON.parse(oidc_state)
    rescue StandardError => e
      rlog.error("[#{temp_request_id}] Unable to parse the JSON in OIDC state \"#{code}\"")
      return json_error('server_error', request_id: temp_request_id)
    end

    state = oidc_state['state'].freeze

    request_id = oidc_state['request_id']
    rlog.info("[#{temp_request_id}] Resuming OIDC flow for request ID \"#{request_id}\"")
    rlog.info("[#{request_id}] OIDC stage 3 token generation for state \"#{code}\"")

    # ----------------------------------------------------------------------------------------------
    # Verify the redirect URI

    # This has to be the same address where the response was sent at the end of stage 2.
    # The RFC says this is OPTIONAL, but just like in stage 1, we require it. We can't
    # even get past stage 1 if the URL is not allowed.
    redirect_uri = params.fetch('redirect_uri', nil)

    unless redirect_uri == oidc_state['redirect_uri']
      rlog.error("[#{request_id}] Mismatching redirect URIs: got \"#{redirect_uri}\", expected \"#{oidc_state['redirect_uri']}\"")
      return json_error('invalid_request', request_id: temp_request_id)
    end

    # From here on, the redirect URI is usable, if needed

    # ----------------------------------------------------------------------------------------------
    # Verify the client ID

    client_id = params.fetch('client_id', nil)

    unless client_id == oidc_state['client_id']
      rlog.error("[#{request_id}] The client ID has changed: got \"#{client_id}\", expected \"#{oidc_state['client_id']}\"")
      return json_error('unauthorized_client', state: state, request_id: request_id)
    end

    # ----------------------------------------------------------------------------------------------
    # Verify the client secret

    external_service = get_external_service(oidc_state['service']['dn'])
    client_secret = params.fetch('client_secret', nil)

    unless client_secret == external_service.secret
      rlog.error("[#{request_id}] Invalid client secret in the request")
      return json_error('unauthorized_client', state: state, request_id: request_id)
    end

    # ----------------------------------------------------------------------------------------------
    # (Re)Load the OIDC configuration

    begin
      client_config = YAML.safe_load(File.read('/etc/puavo-web/oauth2.yml'))
    rescue StandardError => e
      rlog.error("[#{request_id}] Can't parse the OIDC configuration file: #{e}")
      return json_error('server_error', state: state, request_id: request_id)
    end

    # Assume this does not fail, since we've validated everything
    client_config = client_config['oidc_logins'][client_id].freeze

    # ----------------------------------------------------------------------------------------------
    # Verify the scopes

    # TODO: If scopes are specified, they must be compared against the scopes that were
    # specified in the original authorization request. The scopes must be identical or
    # a subset. If they include new scopes, the request must be rejected.

    # TODO: I don't know what to do with the new scopes. Do we use them below, or do we
    # use the original scopes? I don't know. I can't find any specifications for this,
    # nor any examples. RFC 6749 simply mentions it's possible to specify the scopes
    # again this call but fails to elaborate further.

    # ----------------------------------------------------------------------------------------------
    # All good. Build the ID token.

    # TODO: Should this be client-configurable?
    expires_in = 3600
    now = Time.now.utc.to_i

    payload = {
      'iss' => ISSUER,
      'jti' => SecureRandom.uuid,
      'sub' => oidc_state['user']['uuid'],
      'aud' => oidc_state['client_id'],
      'iat' => now,
      'nbf' => now,
      'exp' => now + expires_in,
      'auth_time' => oidc_state['auth_time'],
    }

    if oidc_state.include?('nonce')
      # If the nonce was present in the original request, send it back
      payload['nonce'] = oidc_state['nonce']
    end

    # Collect the user data and append it to the payload
    # TODO: This code is duplicated in the userinfo endpoint. Merge these.
    begin
      organisation = Organisation.by_domain(oidc_state['organisation']['domain'])
      LdapModel.setup(organisation: organisation, credentials: CONFIG['server'])

      user = PuavoRest::User.by_dn(oidc_state['user']['dn'])

      if user.nil?
        rlog.error("[#{request_id}] Cannot find the logged-in user (DN=#{oidc_state['user']['dn']})")
        return json_error('access_denied', state: state, request_id: request_id)
      end

      # Locked users cannot access any resources
      if user.locked || user.removal_request_time
        rlog.error("[#{request_id}] The target user (#{user.username}) is locked or marked for deletion")
        return json_error('access_denied', state: state, request_id: request_id)
      end
    rescue StandardError => e
      rlog.error("[#{request_id}] Could not log in and retrieve the target user: #{e}")
      return json_error('server_error', state: state, request_id: request_id)
    end

    begin
      user_data = gather_user_data(request_id, oidc_state['scopes'], organisation, user)
    rescue StandardError => e
      rlog.error("[#{request_id}] Could not gather the user data for the token: #{e}")
      return json_error('server_error', state: state, request_id: request_id)
    end

    payload.merge!(user_data)

    # Build the access token. Currently it's only usable with the userinfo endpoint,
    # as the scope names are different.
    token = build_access_token(
      request_id,
      subject: oidc_state['user']['uuid'],
      audience: 'puavo-rest-userinfo',      # this token is only usable in the userinfo endpoint
      scopes: oidc_state['scopes'],
      expires_in: expires_in,

      # These are hard to determine afterwards, so stash them in the token
      # (These are for the userinfo endpoint; it works because auth() stores the full
      # token in the credentials data and we can dig these up from it.)
      custom_claims: {
        'organisation_domain' => oidc_state['organisation']['domain'],
        'user_dn' => oidc_state['user']['dn']
      }
    )

    unless token[:success]
      return json_error('invalid_request', request_id: request_id)
    end

    # Load the signing private key. Unlike the public key, this is not kept in memory.
    begin
      private_key = OpenSSL::PKey.read(File.open(CONFIG['oauth2']['token_private_key']))
    rescue StandardError => e
      rlog.error("[#{request_id}] Cannot load the access token signing private key file: #{e}")
      return { success: false }
    end

    rlog.info("[#{request_id}] Issued access token #{token[:jti].inspect} for the user, expires at #{Time.at(token[:expires_at])}")

    out = {
      'access_token' => token[:access_token],
      'token_type' => 'Bearer',
      'expires_in' => expires_in,
      'id_token' => JWT.encode(payload, private_key, 'ES256', { typ: 'at+jwt' }),
      'puavo_request_id' => request_id,
    }

    if oidc_state['scopes_changed']
      # See the stage 2 handler for explanation
      out['scopes'] = oidc_state['scopes'].join(' ')
    end

    headers['Cache-Control'] = 'no-store'
    headers['Pragma'] = 'no-cache'

    json(out)
  end
end   # module OAuth2
end   # module PuavoRest
