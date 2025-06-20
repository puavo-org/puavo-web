# frozen_string_literal: true

# OpenID Connect SSO system

require 'sinatra/r18n'
require 'sinatra/cookies'
require 'addressable/uri'
require 'pg'

require 'securerandom'
require 'openssl'
require 'jwt'

require 'base64'
require 'argon2'

require_relative '../users'

require_relative '../../lib/sso/form_utility'
require_relative '../../lib/sso/sessions'
require_relative '../../lib/sso/mfa'
require_relative '../../lib/oauth2_audit'

require_relative './scopes'
require_relative './utility'

module PuavoRest
module OAuth2

# RFC 9207 issuer identifier
ISSUER = 'https://api.opinsys.fi'

class OpenIDConnect < PuavoSinatra
  register Sinatra::R18n

  include FormUtility
  include SSOSessions
  include MFA

  # New OpenID Connect Authorization Request
  # RFC 6749 section 3.1. says GET requests MUST be supported, while, POST requests MAY
  # be supported. We support both. (The SSO form post action URL is changed.)
  get '/oidc/authorize' do
    openidc_authorization_request
  end

  post '/oidc/authorize' do
    openidc_authorization_request
  end

  # SSO form submission in OpenID Connect mode
  post '/oidc/authorize/post' do
    sso_handle_form_post
  end

  # Called from the MFA form handler
  get '/oidc/authorize/mfa_complete' do
    oidc_authorization_response
  end

  # OIDC ID token / client credentials access token generation
  # (OpenID Connect Stage 3)
  post '/oidc/token' do
    # What kind of a request are we dealing with? We must create a temporary request ID
    # because we cannot access the stored data before validation.
    temp_request_id = make_request_id
    grant_type = params.fetch('grant_type', nil)
    rlog.info("[#{temp_request_id}] OAuth2 token request, grant type: #{grant_type.inspect}")

    case grant_type
      when 'authorization_code'
        oidc_access_token_request(temp_request_id)

      when 'client_credentials'
        client_credentials_grant(temp_request_id)

      else
        rlog.error("[#{temp_request_id}] Unsupported grant type")
        json_error('unsupported_grant_type', request_id: temp_request_id)
    end

    # Not reached
  end

  # OpenID Connect userinfo endpoint. Only OAuth2 access token logins are supported.
  # This is the only place where the access token generated during logins can be used in.
  # https://openid.net/specs/openid-connect-core-1_0.html#UserInfo says we MUST support
  # both GET and POST userinfo requests.
  get '/oidc/userinfo' do
    oidc_handle_userinfo
  end

  post '/oidc/userinfo' do
    oidc_handle_userinfo
  end

  # OpenID Connect SSO session logout
  # TODO: Implement this
  #get '/oidc/authorize/logout' do
  #end

private

  def openidc_authorization_request
    request_id = make_request_id()

    rlog.info("[#{request_id}] New OpenID Connect authorization request")

    # Until the client ID and redirection URI have been validated, we cannot do error redirects.
    # Instead we display an error message in the browser. This matches RFC 6749 section 3.1.2.4.

    # ----------------------------------------------------------------------------------------------
    # Ensure the request parameters contains all the required items and they're not empty

    %w[client_id redirect_uri response_type].each do |k|
      unless params.include?(k)
        # Tested
        rlog.error("[#{request_id}] A required parameter \"#{k}\" is missing from the request parameters")
        rlog.error("[#{request_id}] Request parameters: #{params.inspect}")
        generic_error(t.oauth2.missing_or_invalid_required_parameter(k, request_id))
      end

      v = params.fetch(k, '')

      if v.nil? || v.strip.empty?
        # Tested
        rlog.error("[#{request_id}] A required parameter \"#{k}\" was specified but it's empty")
        rlog.error("[#{request_id}] Request parameters: #{params.inspect}")
        generic_error(t.oauth2.missing_or_invalid_required_parameter(k, request_id))
      end
    end

    # ----------------------------------------------------------------------------------------------
    # Verify the client ID and the target external service

    client_id = params['client_id']
    rlog.info("[#{request_id}] Client ID: #{client_id.inspect}")

    clients = ClientDatabase.new
    client_config = clients.get_client_by_id(request_id, client_id, :login)
    clients.close

    if client_config.nil?
      # Tested
      rlog.error("[#{request_id}] No client found by that ID")
      generic_error(t.oauth2.invalid_client_id(request_id))
    end

    unless client_config['enabled'] == 't'
      # Tested
      rlog.error("[#{request_id}] The client exists but it has been disabled")
      generic_error(t.oauth2.invalid_client_id(request_id))
    end

    # Find the target service
    service_dn = client_config['puavo_service_dn']
    rlog.info("[#{request_id}] Target external service DN: #{service_dn.inspect}")

    external_service = get_external_service(service_dn)

    if external_service.nil?
      # Tested
      rlog.error("[#{request_id}] No external service found by that DN")
      generic_error(t.oauth2.invalid_client_id(request_id))
    end

    rlog.info("[#{request_id}] Target external service name: #{external_service.name.inspect}")

    # ----------------------------------------------------------------------------------------------
    # Verify the redirect URL(s)
    # RFC 6749 section 4.1.1. says this is OPTIONAL, but we require it for security reasons

    redirect_uri = params['redirect_uri']

    rlog.info("[#{request_id}] Redirect URI: #{redirect_uri.inspect}")

    if client_config.fetch('allowed_redirects', []).find { |uri| uri == redirect_uri }.nil?
      # Tested
      rlog.error("[#{request_id}] This redirect URI is not allowed")
      generic_error(t.oauth2.invalid_redirect_uri(request_id))
    end

    rlog.info("[#{request_id}] The redirect URI is valid")

    # The client ID and the redirect URI have been validated. We can now do proper error redirects,
    # as specified in RFC 6479 section 4.1.2.1.

    # ----------------------------------------------------------------------------------------------
    # Check the response type. As per RFC 6749 section 4.1.1, this is REQUIRED
    # and its value must be "code".

    response_type = params.fetch('response_type', nil)

    unless response_type == 'code'
      # Tested
      rlog.error("[#{request_id}] Invalid response type #{response_type.inspect} (expected \"code\")")
      return redirect_error(redirect_uri, 'invalid_request', state: params.fetch('state', nil),
                            request_id: request_id)
    end

    rlog.info("[#{request_id}] The response type is #{response_type.inspect}")

    # ----------------------------------------------------------------------------------------------
    # Verify the scopes

    scopes = Scopes.clean_scopes(request_id, params.fetch('scope', ''), Scopes::BUILTIN_LOGIN_SCOPES, client_config, require_openid: true)

    unless scopes.success
      # Tested
      return redirect_error(redirect_uri, 'invalid_scope', state: params.fetch('state', nil), request_id: request_id)
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
      'original_scopes' => params.fetch('scope', ''),   # for auditing
      'scopes' => scopes.scopes.to_a,
      'scopes_changed' => scopes.changed,       # need to remember this for later responses
      'state' => params.fetch('state', nil),    # the state is merely RECOMMENDED, but not required
      'service' => {
        'dn' => service_dn,
        'domain' => external_service.domain,
      },

      # Not known yet
      'organisation' => nil,
      'user' => nil
    }

    if params.include?('nonce')
      # The nonce is an optional value used to mitigate replay attacks. It is barely mentioned
      # in RFC 6749, but it is mentioned in the full spec. If specified in the request, we must
      # remember it.
      oidc_state['nonce'] = params['nonce']
    end

    state_key = SecureRandom.hex(64)

    rlog.info("[#{request_id}] Initialized OpenID Connect login state #{state_key.inspect}")

    # Stash the state tracking data in Redis
    oidc_redis.set(state_key, oidc_state.to_json, nx: true, ex: PUAVO_OIDC_LOGIN_TIME)

    oidc_try_login(request_id: request_id, state_key: state_key)
  rescue StandardError => e
    # Tested
    rlog.error("[#{request_id}] #{e}")
    generic_error(t.sso.system_error(request_id))
  end

  def oidc_try_login(request_id:, state_key:)
    oidc_state = oidc_redis.get(state_key)

    if oidc_state.nil?
      rlog.error("oidc_try_login(): nothing found in Redis by state key #{state_key.inspect}, halting")
      generic_error(t.sso.system_error(request_id), status: 400)
    end

    oidc_state = JSON.parse(oidc_state)
    request_id = oidc_state['request_id']   # resume original login flow

    # Determine the target external service
    if return_to.nil?
      purge_oidc_state(state_key)
      rlog.error("[#{request_id}] There's no 'return_to' or 'return' parameter in the request URL. Unable to determine the target external service.")
      rlog.error("[#{request_id}] Full original request URL: #{request.url.to_s.inspect}")
      generic_error(t.sso.return_to_missing(request_id), status: 400)
    end

    @external_service = fetch_external_service

    if @external_service.nil?
      purge_oidc_state(state_key)
      rlog.error("[#{request_id}] No target external service found by return_to parameter #{return_to.to_s.inspect}")
      rlog.error("[#{request_id}] Full original request URL: #{request.url.to_s.inspect}")
      generic_error(t.sso.unknown_service(request_id))
    end

    # Verify the trusted service URL status (a trusted service must use a trusted SSO URL)
    @is_trusted = request.path == '/v3/verified_sso'

    rlog.info("[#{request_id}] attempting to log into external service \"#{@external_service.name}\" (#{@external_service.dn.to_s})")

    if @external_service.trusted != @is_trusted
      # No mix-and-matching or service types
      purge_oidc_state(state_key)
      rlog.error("[#{request_id}] Trusted service type mismatch (service trusted=#{@external_service.trusted}, URL verified=#{@is_trusted})")
      rlog.error("[#{request_id}] Full original request URL: #{request.url.to_s.inspect}")
      generic_error(t.sso.state_mismatch(request_id))
    end

    # SSO session login?
    had_session, session_data = session_try_login(request_id, @external_service, type: 'oidc')

    if session_data
      # We have session data. Merge the stored organisation and user data with the new
      # OIDC login data. This effectively bypasses the auth process.
      oidc_state['organisation'] = session_data['organisation']
      oidc_state['user'] = session_data['user']
      oidc_state['had_session'] = true

      return oidc_authorization_response(state_key, oidc_state)
    end

    # Try to log in. Permit multiple different authentication methods.
    begin
      auth_method = auth :basic_auth, :from_post, :kerberos
    rescue KerberosError => err
      # Kerberos authentication failed, present the normal login form
      return sso_render_form(request_id, error_message: t.sso.kerberos_error, exception: err, type: 'oidc', state_key: state_key)
    rescue JSONError => err
      # We get here if all the available authentication methods fail. But since the
      # 'force_error_message' parameter of sso_render_form() is false, we won't
      # display any error messages on the first time. Only after the form has been
      # submitted do the error messages become visible. A bit hacky, but it works.

      # Pass custom error headers to the response login page
      response.headers.merge!(err.headers)

      return sso_render_form(request_id, error_message: t.sso.bad_username_or_pw, exception: err, type: 'oidc', state_key: state_key)
    end

    auth_method = 'username+password' if auth_method == 'from_post'

    # If we get here, the user was authenticated. Either by Kerberos, or by basic auth,
    # or they filled in the username+password form.

    # The authentication time is optional, but we can support it easily. It is specified in
    # https://openid.net/specs/openid-connect-core-1_0.html#IDToken.
    oidc_state['auth_time'] = Time.now.utc.to_i

    user = PuavoRest::User.current
    primary_school = user.school

    # Read organisation data manually instead of using the cached one because
    # enabled external services might be updated.
    organisation = LdapModel.setup(credentials: CONFIG["server"]) do
      PuavoRest::Organisation.by_dn(LdapModel.organisation["dn"])
    end

    # Fill in the missing data in the state
    oidc_state['user'] = {
      'dn' => user.dn.to_s,
      'puavo_id' => user.id.to_i,
      'uuid' => user.uuid,
      'auth_method' => auth_method,
    }

    oidc_state['organisation'] = {
      'domain' => organisation.domain,
      'name' => organisation.name,
      'dn' => organisation.dn.to_s,
    }

    # This needs to be remembered, so we don't create double sessions
    oidc_state['had_session'] = had_session

    # Update the stored session data
    oidc_redis.set(state_key, oidc_state.to_json, ex: PUAVO_OIDC_LOGIN_TIME)

    school_allows = Array(primary_school["external_services"]).
      include?(@external_service["dn"])
    organisation_allows = Array(organisation["external_services"]).
      include?(@external_service["dn"])

    if not (school_allows || organisation_allows)
      return sso_render_form(request_id, error_message: t.sso.service_not_activated, type: 'oidc', state_key: state_key)
    end

    # Block logins from users who don't have a verified email address, if the service is trusted
    if @external_service.trusted && @is_trusted
      rlog.info("[#{request_id}] this trusted service requires a verified address and we're in a verified SSO form")

      if Array(user.verified_email || []).empty?
        rlog.error("[#{request_id}] the current user does NOT have a verified address!")
        org = organisation.domain.split(".")[0]
        return sso_render_form(request_id, error_message: t.sso.verified_address_missing("https://#{org}.opinsys.fi/users/profile/edit"), force_error_message: true, type: 'oidc', state_key: state_key)
      end

      rlog.info("[#{request_id}] the user has a verified email address")
    end

    rlog.info("[#{request_id}] SSO login ok")

    if user.mfa_enabled == true
      # Take a detour first and ask for the MFA code

      # Unlike SSO session keys, this is not stored in cookies. It briefly appears in the
      # URL when we redirect the browser to the MFA form, but after that, it's only part of
      # the form data. No information can leak through it.
      session_key = SecureRandom.hex(64)

      rlog.info("[#{request_id}] the user has MFA enabled, starting MFA login session \"#{session_key}\"")

      mfa_create_session(
        session_key,
        user.uuid,
        {
          type: 'oidc',

          # Needed to validate the code and do the redirect
          request_id: request_id,
          user_uuid: user.uuid,
          original_url: request.url.to_s,

          state_key: state_key,
        }
      )

      # Redirect the browser to the MFA form
      mfa_url = URI(request.url)
      mfa_url.path = '/v3/mfa'
      mfa_url.query = "token=#{session_key}"

      redirect mfa_url
    else
      # Normal login
      oidc_authorization_response(state_key)
    end
  rescue StandardError => e
    purge_oidc_state(state_key)
    rlog.error("[#{request_id}] generic login error: #{e}")
    generic_error(t.sso.system_error(request_id))
  end

  # Stage 2: Authorization Response (RFC 6749 section 4.1.2.)
  # We get here from the login/MFA form, or directly from stage 1 if an SSO session existed
  # or Kerberos authentication succeeded. In any case, it's a browser redirect.
  def oidc_authorization_response(state_key=nil, session_data=nil)
    temp_request_id = make_request_id()

    state_key = params.fetch('state_key', '') unless state_key

    if session_data
      # Resume existing session
      oidc_state = session_data
      rlog.info('[#{temp_request_id}] oidc_authorization_response(): loading data from SSO session instead of Redis')
    else
      # Get and delete the login data from Redis
      oidc_state = oidc_redis.get(state_key)

      if oidc_state.nil?
        rlog.error("[#{temp_request_id}] oidc_authorization_response(): nothing found in Redis by state key #{state_key.inspect}, halting")
        generic_error(t.sso.system_error(temp_request_id), status: 400)
      end

      oidc_state = JSON.parse(oidc_state)
    end

    # Delete the data as soon as possible, to prevent replay attacks
    oidc_redis.del(state_key)

    request_id = oidc_state['request_id']
    rlog.info("[#{temp_request_id}] oidc_authorization_response(): resuming login flow #{request_id}")

    # OpenID Connect sessions must be created here, MFA or not
    session_create(
      request_id,
      oidc_state['organisation']['name'],
      oidc_state['service']['domain'],
      oidc_state['service']['dn'],
      oidc_state['user']['dn'],
      {
        'organisation' => oidc_state['organisation'],
        'service' => oidc_state['service'],
        'puavo_id' => oidc_state['user']['puavo_id'],
        'user' => oidc_state['user']
      },
      oidc_state['had_session'],
    )

    rlog.info("[#{request_id}] Generating the authorization response URI, state key #{state_key.inspect}")

    # Store the data again in Redis, but under a different key this time.
    # The stage 3 call must use this code.
    code = SecureRandom.hex(64)
    oidc_redis.set(code, oidc_state.to_json, nx: true, ex: PUAVO_OIDC_LOGIN_TIME)
    rlog.info("[#{request_id}] Initialized OIDC authorization response -> authorization token request tracking state #{code.inspect}")

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

    rlog.info("[#{request_id}] Redirecting the browser to \"#{redirect_uri.to_s}\"")

    redirect redirect_uri
  end

  # ------------------------------------------------------------------------------------------------
  # Stage 3: Access Token Request (RFC 6749 section 4.1.3.)

  # Generate ID and access tokens for the client
  def oidc_access_token_request(temp_request_id)
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
      rlog.error("[#{temp_request_id}] Unable to parse the JSON in OIDC state \"#{code}\": #{e}")
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
      rlog.error("[#{request_id}] Mismatching redirect URIs: got \"#{redirect_uri}\", "  \
                 "expected \"#{oidc_state['redirect_uri']}\"")
      return json_error('invalid_request', request_id: temp_request_id)
    end

    # From here on, the redirect URI is usable, if needed

    # ----------------------------------------------------------------------------------------------
    # Verify the client ID and secret

    client_id = params.fetch('client_id', nil)

    unless client_id == oidc_state['client_id']
      rlog.error("[#{request_id}] The client ID has changed: got \"#{client_id}\", " \
                 "expected \"#{oidc_state['client_id']}\"")
      return json_error('unauthorized_client', state: state, request_id: request_id)
    end

    external_service = get_external_service(oidc_state['service']['dn'])
    client_secret = params.fetch('client_secret', nil)

    if external_service.secret.start_with?('$argon2')
      # Secure Argon2 hash comparison
      match = Argon2::Password.verify_password(client_secret, external_service.secret)
      was_hashed = true
    else
      # Insecure plaintext comparison
      match = client_secret == external_service.secret
      was_hashed = false
    end

    unless match
      # Tested
      rlog.error("[#{request_id}] Invalid client secret in the request (using hashed secret: #{was_hashed})")
      return json_error('unauthorized_client', state: state, request_id: request_id)
    end

    rlog.info("[#{request_id}] Client authenticated (using hashed secret: #{was_hashed})")

    # ----------------------------------------------------------------------------------------------
    # Re-verify the client configuration

    clients = ClientDatabase.new
    client_config = clients.get_client_by_id(request_id, client_id, :login)
    clients.close

    if client_config.nil?
      rlog.error("[#{request_id}] Unknown/invalid client (it existed in stage 1)")
      return json_error('unauthorized_client', state: state, request_id: request_id)
    end

    unless client_config['enabled'] == 't'
      rlog.error("[#{request_id}] This client exists but it has been disabled (it was enabled in stage 1)")
      return json_error('unauthorized_client', state: state, request_id: request_id)
    end

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
      'auth_time' => oidc_state['auth_time']
    }

    if oidc_state.include?('nonce')
      # If the nonce was present in the original request, send it back
      payload['nonce'] = oidc_state['nonce']
    end

    # Collect the user data and append it to the payload
    begin
      error, organisation, user = get_user_in_domain(request_id: request_id,
                                                     domain: oidc_state['organisation']['domain'],
                                                     dn: oidc_state['user']['dn'],
                                                     ldap_credentials: CONFIG['server'])

      unless error.nil?
        return json_error(error, state: state, request_id: request_id)
      end
    rescue StandardError => e
      rlog.error("[#{request_id}] Could not retrieve the target user: #{e}")
      return json_error('server_error', state: state, request_id: request_id)
    end

    begin
      user_data = gather_user_data(request_id, oidc_state['scopes'], oidc_state['user']['auth_method'], organisation, user)
    rescue StandardError => e
      rlog.error("[#{request_id}] Could not gather the user data: #{e}")
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
        'allowed_endpoints' => ['/oidc/userinfo'],
        'organisation_domain' => oidc_state['organisation']['domain'],
        'user_dn' => oidc_state['user']['dn']
      }
    )

    unless token[:success]
      return json_error('invalid_request', request_id: request_id)
    end

    # Load the signing private key. Unlike the public key, this is not kept in memory.
    begin
      private_key = OpenSSL::PKey.read(File.open(CONFIG['oauth2']['token_key']['private_file']))
    rescue StandardError => e
      rlog.error("[#{request_id}] Cannot load the access token signing private key file: #{e}")
      return json_error('server_error', state: state, request_id: request_id)
    end

    rlog.info("[#{request_id}] Issued access token #{token[:raw_token]['jti'].inspect} " \
              "for the user, expires at #{Time.at(token[:expires_at])}")

    audit_issued_id_token(request_id,
                          client_id: client_id,
                          ldap_user_dn: CONFIG['server'][:dn],
                          raw_requested_scopes: oidc_state['original_scopes'],
                          issued_scopes: oidc_state['scopes'],
                          redirect_uri: oidc_state['redirect_uri'],
                          raw_token: payload,
                          request: request)

    audit_issued_access_token(request_id,
                              client_id: client_id,
                              ldap_user_dn: CONFIG['server'][:dn],
                              raw_requested_scopes: oidc_state['original_scopes'],
                              raw_token: token[:raw_token],
                              request: request)

    # Build and return the token data
    out = {
      'access_token' => token[:access_token],
      'token_type' => 'Bearer',
      'expires_in' => expires_in,
      'id_token' => JWT.encode(payload, private_key, 'ES256', { typ: 'at+jwt' }),
      'puavo_request_id' => request_id
    }

    if oidc_state['scopes_changed']
      # See the stage 2 handler for explanation
      out['scopes'] = oidc_state['scopes'].join(' ')
    end

    headers['Cache-Control'] = 'no-store'
    headers['Pragma'] = 'no-cache'

    json(out)
  rescue StandardError => e
    rlog.info("[#{request_id}] Unhandled exception: #{e}")
    return json_error('server_error', state: state, request_id: request_id)
  end

  def client_credentials_grant(request_id)
    rlog.info("[#{request_id}] This is a client credentials grant request")

    # RFC 6749 section 2.2.
    content_type = request.env.fetch('CONTENT_TYPE', nil)

    unless content_type == 'application/x-www-form-urlencoded'
      rlog.error("[#{request_id}] Received a client_credentials request with an incorrect " \
                 "Content-Type header (#{content_type.inspect})")
      return json_error('invalid_request', request_id: request_id)
    end

    # ----------------------------------------------------------------------------------------------
    # Load client credentials from the request

    # TODO: We need to support other client authorization systems

    unless request.env.include?('HTTP_AUTHORIZATION')
      rlog.error("[#{request_id}] Received a client_credentials request without an " \
                 "HTTP_AUTHORIZATION header")
      return json_error('invalid_request', request_id: request_id)
    end

    begin
      credentials = request.env.fetch('HTTP_AUTHORIZATION', '').split
      credentials = Base64.strict_decode64(credentials[1])
      credentials = credentials.split(':')

      if credentials.count != 2
        rlog.error("[#{request_id}] the HTTP_AUTHORIZATION header does not contain a valid " \
                   "client_id:password combo")
        return json_error('invalid_request', request_id: request_id)
      end
    rescue StandardError => e
      rlog.error("[#{request_id}] Could not parse the HTTP_AUTHORIZATION header: #{e}")
      rlog.error("[#{request_id}] Raw header: #{request.env['HTTP_AUTHORIZATION'].inspect}")
      return json_error('invalid_request', request_id: request_id)
    end

    # ----------------------------------------------------------------------------------------------
    # Authenticate the client

    rlog.info("[#{request_id}] Client ID: #{credentials[0].inspect}")

    clients = ClientDatabase.new
    client_config = clients.get_client_by_id(request_id, credentials[0], :token)
    clients.close

    if client_config.nil?
      rlog.error("[#{request_id}] Unknown/invalid client")
      return json_error('unauthorized_client', request_id: request_id)
    end

    unless client_config['enabled'] == 't'
      rlog.error("[#{request_id}] This client exists but it has been disabled")
      return json_error('unauthorized_client', request_id: request_id)
    end

    hashed_password = client_config.fetch('client_password', nil)

    if hashed_password.nil? || hashed_password.strip.empty?
      rlog.error("[#{request_id}] Empty hashed password specified in the database for a " \
                 "token client, refusing access")
      return json_error('unauthorized_client', request_id: request_id)
    end

    unless Argon2::Password.verify_password(credentials[1], hashed_password)
      rlog.error("[#{request_id}] Invalid client password")
      return json_error('unauthorized_client', request_id: request_id)
    end

    rlog.info("[#{request_id}] Client authorized")

    # ----------------------------------------------------------------------------------------------
    # Validate the scopes. RFC 6479 says these are optional for client credential requests,
    # but we require them. RFC 6479 section 3.3. says that if the scopes cannot be used,
    # we must either use default scopes or fail the request. We have no default scopes,
    # so we can only fail the request.

    # TODO: Is the "openid" scope required here?
    scopes = Scopes.clean_scopes(request_id, params.fetch('scope', ''), Scopes::BUILTIN_PUAVO_OAUTH2_SCOPES,
                                 client_config, require_openid: false)

    unless scopes.success
      return json_error('invalid_scope', request_id: request_id)
    end

    if scopes.scopes.empty?
      rlog.error("[#{request_id}] The cleaned-up scopes list is completely empty")
      return json_error('invalid_scope', request_id: request_id)
    end

    # ----------------------------------------------------------------------------------------------
    # Firewalling

    custom_claims = {}

    # Organisation restriction
    if client_config.include?('allowed_organisations') &&
        !client_config['allowed_organisations'].nil? &&
        !client_config['allowed_organisations'].empty?
      custom_claims['allowed_organisations'] = Array(client_config['allowed_organisations'])
      rlog.info("[#{request_id}] Token is only allowed in these organisations: " \
                "#{custom_claims['allowed_organisations'].inspect}")
    end

    # Endpoint restriction
    if client_config.include?('allowed_endpoints') &&
        !client_config['allowed_endpoints'].nil? &&
        !client_config['allowed_endpoints'].empty?
      custom_claims['allowed_endpoints'] = Array(client_config['allowed_endpoints'])
      rlog.info("[#{request_id}] Token is only allowed in these endpoints: " \
                "#{custom_claims['allowed_endpoints'].inspect}")
    end

    # ----------------------------------------------------------------------------------------------
    # Generate the token. Put it in a JWT and sign the JWT with a private key,
    # so we now have a self-validating token.

    expires_in = client_config['expires_in'].to_i

    token = build_access_token(
      request_id,
      client_id: credentials[0],
      subject: credentials[0],
      scopes: scopes[:scopes],
      expires_in: expires_in,
      custom_claims: custom_claims
    )

    unless token[:success]
      return json_error('invalid_request', request_id: request_id)
    end

    out = {
      'access_token' => token[:access_token],
      'token_type' => 'Bearer',
      'expires_in' => expires_in,
      'puavo_request_id' => request_id
    }

    rlog.info("[#{request_id}] Issued access token #{token[:raw_token]['jti'].inspect}, " \
              "expires at #{Time.at(token[:expires_at])}")

    audit_issued_access_token(request_id,
                              ldap_user_dn: CONFIG['server'][:dn],
                              client_id: credentials[0],
                              raw_requested_scopes: params.fetch('scope', ''),
                              raw_token: token[:raw_token],
                              request: request)

    headers['Cache-Control'] = 'no-store'
    headers['Pragma'] = 'no-cache'

    json(out)
  end

  def oidc_handle_userinfo
    oauth2 scopes: %w[openid profile], audience: 'puavo-rest-userinfo'
    auth :oauth2_token

    request_id = make_request_id()

    access_token = LdapModel.settings[:credentials][:access_token]

    rlog.info("[#{request_id}] Returning userinfo data for user \"#{access_token['user_dn']}\" " \
              "in organisation \"#{access_token['organisation_domain']}\"")

    # Get the user data
    begin
      error, organisation, user = get_user_in_domain(request_id: request_id,
                                                     domain: access_token['organisation_domain'],
                                                     dn: access_token['user_dn'],
                                                     ldap_credentials: CONFIG['server'])

      unless error.nil?
        return json_error(error, request_id: request_id)
      end
    rescue StandardError => e
      rlog.error("[#{request_id}] Could not retrieve the target user: #{e}")
      return json_error('server_error', request_id: request_id)
    end

    begin
      user_data = gather_user_data(request_id, access_token['scopes'], nil, organisation, user)
    rescue StandardError => e
      rlog.error("[#{request_id}] Could not gather the user data: #{e}")
      return json_error('server_error', request_id: request_id)
    end

    # Return it
    headers['Cache-Control'] = 'no-store'
    headers['Pragma'] = 'no-cache'

    json(user_data)
  end

  def get_user_in_domain(request_id:, domain:, dn:, ldap_credentials:)
    organisation = Organisation.by_domain(domain)
    LdapModel.setup(organisation: organisation, credentials: ldap_credentials)

    user = PuavoRest::User.by_dn(dn)

    if user.nil?
      rlog.error("[#{request_id}] Cannot find user by DN #{dn.inspect}")
      return 'access_denied', nil, nil
    end

    # Locked users cannot access any resources
    if user.locked || user.removal_request_time
      rlog.error("[#{request_id}] The target user #{dn.inspect} is locked or marked for deletion")
      return 'access_denied', nil, nil
    end

    return nil, organisation, user
  end

  def gather_user_data(request_id, scopes, auth_method, organisation, user)
    out = {}
    school_cache = {}

    if scopes.include?('profile')
      # Try to extract the modification timestamp from the LDAP operational attributes
      begin
        extra = User.raw_filter("ou=People,#{organisation['base']}",
                                "(puavoId=#{user.id})",
                                ['modifyTimestamp'])
        updated_at = Time.parse(extra[0]['modifyTimestamp'][0]).to_i
      rescue StandardError => e
        rlog.warn("[#{request_id}] Cannot determine the user's last modification time: #{e}")
        updated_at = nil
      end
    end

    external_data = {}
    mpass_charging_state = nil
    mpass_charging_school = nil

    if user.external_data
      begin
        external_data = JSON.parse(user.external_data)
      rescue StandardError => e
        rlog.warn("[#{request_id}] Unable to parse user's external data: #{e}")
      end
    end

    has_mpass = scopes.include?('puavo.read.userinfo.mpassid')

    if has_mpass && external_data.include?('materials_charge')
      # Parse MPASSid materials charge info
      mpass_charging_state, mpass_charging_school = external_data['materials_charge'].split(';')
    end

    # Include LDAP DNs in the response?
    has_ldap = scopes.include?('puavo.read.userinfo.ldap')

    if scopes.include?('profile')
      # Standard claims
      out['given_name'] = user.first_name
      out['family_name'] = user.last_name
      out['name'] = "#{user.first_name} #{user.last_name}"
      out['preferred_username'] = user.username
      out['updated_at'] = updated_at unless updated_at.nil?
      out['locale'] = user.locale
      out['zoneinfo'] = user.timezone

      # Puavo-specific claims
      out['puavo.uuid'] = user.uuid
      out['puavo.puavoid'] = user.puavo_id.to_i
      out['puavo.ldap_dn'] = user.dn if has_ldap
      out['puavo.external_id'] = user.external_id if user.external_id
      out['puavo.learner_id'] = user.learner_id if user.learner_id
      out['puavo.roles'] = user.roles
      out['puavo.authenticated_using'] = auth_method || nil

      if scopes.include?('puavo.read.userinfo.primus')
        # External Primus card ID (not always available)
        out['puavo.primus_card_id'] = external_data.fetch('primus_card_id', nil)
      end
    end

    if scopes.include?('email')
      # Prefer the primary email address if possible
      unless user.primary_email.nil?
        out['email'] = user.primary_email
        out['email_verified'] = user.verified_email && user.verified_email.include?(user.primary_email)
      else
        unless user.verified_email.empty?
          # This should not really happen, as the first verified email is
          # also the primary email
          out['email'] = user.verified_email[0]
          out['email_verified'] = true
        else
          # Just pick the first available address
          if user.email && !user.email.empty?
            out['email'] = user.email[0]
          else
            out['email'] = nil
          end

          out['email_verified'] = false
        end
      end
    end

    if scopes.include?('phone') && !user.telephone_number.empty?
      out['phone_number'] = user.telephone_number[0]
    end

    if scopes.include?('puavo.read.userinfo.schools')
      schools = []

      user.schools.each do |s|
        school_cache[s.dn] = s

        school = {
          'name' => s.name,
          'abbreviation' => s.abbreviation,
          'puavoid' => s.puavo_id.to_i,
          'external_id' => s.external_id,
          'school_code' => s.school_code,
          'oid' => s.school_oid,
          'primary' => user.primary_school_dn == s.dn
        }

        if has_mpass && s.school_code == mpass_charging_school
          school['mpass_learning_materials_charge'] = mpass_charging_state
        end

        school['ldap_dn'] = s.dn if has_ldap

        schools << school
      end

      out['puavo.schools'] = schools
    end

    if scopes.include?('puavo.read.userinfo.groups')
      have_schools = scopes.include?('puavo.read.userinfo.schools')
      groups = []

      user.groups.each do |g|
        group = {
          'name' => g.name,
          'abbreviation' => g.abbreviation,
          'puavoid' => g.id.to_i,
          'external_id' => g.external_id,
          'type' => g.type
        }

        group['ldap_dn'] = g.dn if has_ldap
        group['school_abbreviation'] = get_school(g.school_dn, school_cache).abbreviation if have_schools

        groups << group
      end

      out['puavo.groups'] = groups
    end

    if scopes.include?('puavo.read.userinfo.organisation')
      org = {
        'name' => organisation.name,
        'domain' => organisation.domain
      }

      org['ldap_dn'] = organisation.dn if has_ldap

      out['puavo.organisation'] = org
    end

    is_owner = organisation.owner.include?(user.dn)

    if scopes.include?('puavo.read.userinfo.admin')
      out['puavo.is_organisation_owner'] = is_owner

      if scopes.include?('puavo.read.userinfo.schools')
        out['puavo.admin_in_schools'] = user.admin_of_school_dns.collect do |dn|
          get_school(dn, school_cache).abbreviation
        end
      end
    end

    if scopes.include?('puavo.read.userinfo.security')
      out['puavo.mfa_enabled'] = user.mfa_enabled == true
      out['puavo.super_owner'] = is_owner && super_owner?(user.username)
    end

    school_cache = nil
    out
  end

  # School searches are slow, so cache them
  def get_school(dn, cache)
    cache[dn] = School.by_dn(dn) unless cache.include?(dn)
    cache[dn]
  end

  def build_access_token(request_id,
                         scopes: [],
                         client_id: nil,
                         subject: nil,
                         audience: 'puavo-rest-v4',
                         expires_in: 3600,
                         custom_claims: nil)
    now = Time.now.utc.to_i

    token_claims = {
      'jti' => SecureRandom.uuid,
      'iat' => now,
      'nbf' => now,
      'exp' => now + expires_in,
      'iss' => ISSUER,
      'sub' => subject,
      'aud' => audience,
      'scopes' => scopes.join(' ')
    }

    token_claims['client_id'] = client_id if client_id

    token_claims.merge!(custom_claims) if custom_claims.is_a?(Hash)

    # Load the signing private key. Unlike the public key, this is not kept in memory.
    begin
      private_key = OpenSSL::PKey.read(File.open(CONFIG['oauth2']['token_key']['private_file']))
    rescue StandardError => e
      rlog.error("[#{request_id}] Cannot load the access token signing private key file: #{e}")
      return { success: false }
    end

    # TODO: Support encrypted tokens with JWE? The "jwe" gem is already installed.
    # TODO: Install the jwt-eddsa gem and use EdDSA signing? Is it compatible with JWT?

    # Sign the token data using the private key. RFC 9068 section 2.1. says the "typ" value
    # SHOULD be "at+jwt", but the JWT gem does not set it, so let's set it manually.
    # (I have no idea what I'm doing.)
    access_token = JWT.encode(token_claims, private_key, 'ES256', { typ: 'at+jwt' })

    {
      success: true,
      access_token: access_token,
      raw_token: token_claims,        # some places, like auditing, needs to see the raw data
      expires_at: now + expires_in
    }
  end

  def get_external_service(dn)
    LdapModel.setup(credentials: CONFIG['server']) do
      PuavoRest::ExternalService.by_dn(dn)
    end
  end

  # Retrieve the OpenID Connect login session data from Redis
  def oidc_redis
    Redis::Namespace.new('oidc_session', redis: REDIS_CONNECTION)
  end

  def purge_oidc_state(state_key)
    oidc_redis.del(state_key) if state_key
  rescue StandardError => e
    rlog.error("purge_oidc_state(): could not purge OIDC state by key #{state_key.inspect}")
  end

  # RFC 6749 section 4.1.2.1.
  def redirect_error(redirect_uri, error, error_description: nil, error_uri: nil, state: nil, request_id: nil)
    out = {}

    out['error'] = error
    out['error_description'] = error_description if error_description
    out['error_uri'] = error_uri if error_uri
    out['state'] = state if state
    out['puavo_request_id'] = request_id if request_id
    out['iss'] = ISSUER

    uri = URI(redirect_uri)
    uri.query = URI.encode_www_form(out)

    redirect(uri)
  end

  # RFC 6749 section 5.2.
  def json_error(error, http_status: 400, error_description: nil, error_uri: nil, state: nil, request_id: nil)
    out = {}

    out['error'] = error
    out['error_description'] = error_description if error_description
    out['error_uri'] = error_uri if error_uri
    out['state'] = state if state
    out['puavo_request_id'] = request_id if request_id
    out['iss'] = ISSUER

    headers['Cache-Control'] = 'no-store'
    headers['Pragma'] = 'no-cache'

    return http_status, json(out)
  rescue StandardError => e
    puts e
  end

  helpers do
    def raw(string)
      return string
    end

    def token_tag(token)
      # FIXME
    end

    def form_authenticity_token
      # FIXME
    end
  end

end   # class OpenIDConnect

end   # module OAuth2
end   # module PuavoRest
