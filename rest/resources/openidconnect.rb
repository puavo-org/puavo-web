# OpenID Connect SSO system

require 'securerandom'

require_relative '../lib/login/utility'

module PuavoRest

# Known built-in scopes
BUILTIN_SCOPES = %w(
  openid
  profile
  email
  phone
  organisation
  schools
  groups
  admins
  ldap
  security
).to_set.freeze

class OpenIDConnect < PuavoSinatra
  register Sinatra::R18n

  include PuavoLoginUtility
  include PuavoLoginSession

  # ------------------------------------------------------------------------------------------------
  # Stage 1: Authorization request

  # Accept both GET and POST authorization requests
  get '/oidc/authorize' do
    oidc_authorization_request
  end

  post '/oidc/authorize' do
    oidc_authorization_request
  end

  def oidc_authorization_request
    request_id = make_request_id

    rlog.info("[#{request_id}] New OpenID Connect authorization request")

    # Until the client ID and redirection URI have been validated, we cannot do error redirects.
    # Instead we display an error message in the browser. This matches RFC 6749 section 3.1.2.4.

    # ----------------------------------------------------------------------------------------------
    # (Re)Load the OpenID Connect configuration file

    begin
      oidc_config = YAML.safe_load(File.read('/etc/puavo-web/oidc.yml')).freeze
    rescue StandardError => e
      rlog.error("[#{request_id}] Can't parse the OIDC configuration file: #{e}")

      # Don't reveal the exact reason
      generic_error(t.sso.unspecified_error(request_id))
    end

    # ----------------------------------------------------------------------------------------------
    # Verify the client ID and the target external service

    client_id = params.fetch('client_id', nil)

    rlog.info("[#{request_id}] Client ID: #{client_id.inspect}")

    unless oidc_config['clients'].include?(client_id)
      rlog.error("[#{request_id}] Unknown/invalid client")
      generic_error(t.sso.invalid_client_id(request_id))
    end

    client_config = oidc_config['clients'][client_id].freeze

    # Find the target service
    service_dn = client_config['puavo_service']
    external_service = get_external_service(service_dn)

    if external_service.nil?
      rlog.error("[#{request_id}] Cannot find the external service by DN \"#{service_dn}\"")
      generic_error(t.sso.invalid_client_id(request_id))
    end

    rlog.info("[#{request_id}] Target external service: name=#{external_service.name.inspect}, DN=#{external_service.dn.inspect}")

    # ----------------------------------------------------------------------------------------------
    # Verify the redirect URL(s)

    # RFC 6749 section 4.1.1. says this is optional, but we require it

    redirect_uri = params['redirect_uri']

    if client_config.fetch('allowed_redirect_uris', []).find { |uri| uri == redirect_uri }.nil?
      rlog.error("[#{request_id}] Redirect URI \"#{redirect_uri}\" is not allowed")
      generic_error(t.sso.invalid_redirect_uri(request_id))
    end

    rlog.info("[#{request_id}] Redirect URI: #{redirect_uri.inspect}")

    # The client ID and the redirect URI have been validated. We can now do proper error redirects,
    # as specified in RFC 6479 section 4.1.2.1.

    # ----------------------------------------------------------------------------------------------
    # Check the response type

    response_type = params.fetch('response_type', nil)

    unless response_type == 'code'
      rlog.error("[#{request_id}] Unknown response type \"#{response_type}\", don't know how to handle it")
      return redirect_error(redirect_uri, 400, 'invalid_request', state: params.fetch('state', nil), request_id: request_id)
    end

    # ----------------------------------------------------------------------------------------------
    # Verify the scopes

    scopes = clean_scopes(params.fetch('scope', ''), oidc_config, client_config, request_id)

    unless scopes[:success]
      return redirect_error(redirect_uri, 400, 'invalid_scope', state: params.fetch('state', nil), request_id: request_id)
    end

    # ----------------------------------------------------------------------------------------------
    # Build Redis data

    # This structure tracks the user's OpenID Connect authorization session. While separate
    # from the "login session" that exists during the login form (and the MFA form, if enabled),
    # it is briefly stored inside the login session data when the forms are displayed. It is
    # deleted after the OIDC access token (or the initial JWT) has been generated.
    oidc_state = {
      'request_id' => request_id,
      'client_id' => client_id,
      'redirect_uri' => redirect_uri,
      'scopes' => scopes[:scopes],
      'scopes_changed' => scopes[:changed],     # remember this for later responses
      'state' => params.fetch('state', nil),

      # These will be copied from the login session once it completes (we need to persist these
      # until the initial JWT/access token has been generated)
      'service' => nil,
      'organisation' => nil,
      'user' => nil,
    }

    if params.include?('nonce')
      oidc_state['nonce'] = params['nonce']
    end

    login_key = SecureRandom.hex(64)

    rlog.info("[#{request_id}] Login key: #{login_key.inspect}")

    begin
      # Use the same request ID for everything
      login_data = login_create_data(request_id, external_service, is_trusted: external_service.trusted, next_stage: '/oidc/stage2')

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
      redirect "/v3/sso/login?login_key=#{login_key}"
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
  # Stage 2: Generate the authorization request response

  # We get here from the login form, or directly from stage 1 if a session existed
  get '/oidc/stage2' do
    # Get and delete the login data from Redis
    login_key = params.fetch('login_key', '')
    login_data = login_get_data(login_key, delete_immediately: true)
    request_id = login_data['request_id']
    rlog.info("[#{request_id}] OpenID Connect authorization request continues, login key was #{login_key.inspect}")

    # Copy the OpenID Connect session state from the login data
    oidc_state = login_data['oidc_state']
    oidc_state['service'] = login_data['service']
    oidc_state['organisation'] = login_data['organisation']
    oidc_state['user'] = login_data['user']

    # Optional (but we can support it easily)
    oidc_state['auth_time'] = Time.now.utc.to_i

    # Create an SSO session if possible
    session_create(login_key, login_data, {
      'service' => login_data['service'],
      'organisation' => login_data['organisation'],
      'user' => login_data['user'],
    })

    # Generate the session code and stash everything in Redis
    code = SecureRandom.hex(64)
    _oidc_redis.set(code, oidc_state.to_json, nx: true, ex: PUAVO_OIDC_LOGIN_TIME)
    rlog.info("[#{request_id}] Generated OIDC session #{code}")

    # Return to the caller
    redirect_uri = URI(oidc_state['redirect_uri'])

    query = {
      'code' => code,
      'state' => oidc_state['state']
    }

    if oidc_state['scopes_changed']
      # RFC 6749 section 3.3. says the scopes must be included in the response if
      # it is different from the scopes the client specified. The spec is unclear
      # how the scopes should be encoded (array or list). Return them in the way
      # they are specified in the request.
      query['scope'] = oidc_state['scopes'].join(' ')
    end

    redirect_uri.query = URI.encode_www_form(query)

    redirect redirect_uri
  end

  # ------------------------------------------------------------------------------------------------
  # Stage 3: ID token and access token requests

  # The client calls this after the authorization is complete
  post '/oidc/token' do
    # What kind of a request are we dealing with?
    temp_request_id = make_request_id
    grant_type = params.fetch('grant_type', nil)
    rlog.info("OpenID Connect access token request, grant type: #{grant_type.inspect}")

    case grant_type
      when 'client_credentials'
        handle_client_credentials

      when 'authorization_code'
        handle_authorization_code

      else
        rlog.error("[#{temp_request_id}] Grant type of \"#{grant_type}\" is not supported")
        json_error('unsupported_grant_type', request_id: temp_request_id)
    end
  end

  # Handles a "client_credentials" request
  # TODO: This call requires further authentication. Clients need to authenticate themselves
  # before a token is generated. Also, client A cannot generate access tokens for client B.
  def handle_client_credentials
    request_id = make_request_id

    content_type = request.env.fetch('CONTENT_TYPE', nil)

    unless content_type == 'application/x-www-form-urlencoded'
      rlog.error("[#{request_id}] Received a client_credentials request with an incorrect Content-Type header (#{content_type.inspect})")
      return json_error('invalid_request', request_id: request_id)
    end

    # ----------------------------------------------------------------------------------------------
    # Verify and authorize the client

    unless request.env.include?('HTTP_AUTHORIZATION')
      rlog.error("[#{request_id}] Received a client_credentials request without an HTTP_AUTHORIZATION header")
      return json_error('invalid_request', request_id: request_id)
    end

    begin
      credentials = request.env.fetch('HTTP_AUTHORIZATION', '').split(' ')
      credentials = Base64::strict_decode64(credentials[1])
      credentials = credentials.split(':')
      raise StandardError.new('the HTTP_AUTHORIZATION header does not contain a username:password combo') if credentials.count != 2
    rescue StandardError => e
      rlog.error("[#{request_id}] Received a client_credentials request with a malformed authentication header: #{e}")
      rlog.error("[#{request_id}] Raw header: #{request.env['HTTP_AUTHORIZATION'].inspect}")
      return json_error('invalid_request', request_id: request_id)
    end

    # ----------------------------------------------------------------------------------------------
    # (Re)Load the OpenID Connect configuration file

    begin
      oidc_config = YAML.safe_load(File.read('/etc/puavo-web/oidc.yml')).freeze
    rescue StandardError => e
      rlog.error("[#{request_id}] Can't parse the OIDC configuration file: #{e}")
      return json_error('unauthorized_client', request_id: request_id)
    end

    # ----------------------------------------------------------------------------------------------
    # Verify the client ID and the target service

    rlog.info("[#{request_id}] client_id: #{credentials[0].inspect}")

    unless oidc_config['clients'].include?(credentials[0])
      rlog.error("[#{request_id}] Unknown/invalid client")
      return json_error('unauthorized_client', request_id: request_id)
    end

    client_config = oidc_config['clients'][credentials[0]].freeze

    # Find the target service
    service_dn = client_config['puavo_service']
    external_service = get_external_service(service_dn)

    if external_service.nil?
      rlog.error("[#{request_id}] Cannot find the external service by DN \"#{service_dn}\"")
      return json_error('unauthorized_client', request_id: request_id)
    end

    # ----------------------------------------------------------------------------------------------
    # Verify the client secret

    unless credentials[1] == external_service.secret
      rlog.error("[#{request_id}] Invalid client secret")
      return json_error('unauthorized_client', request_id: request_id)
    end

    # ----------------------------------------------------------------------------------------------
    # Generate the access token

    # TODO: The access token must be stored in Redis. We don't have yet any endpoint that
    # needs it, so this part has not been implemented yet.
    access_token = SecureRandom.hex(64)

    rlog.info("[#{request_id}] Generated access token #{access_token.inspect}")

    out = {
      'access_token' => access_token,
      'token_type' => 'Bearer',
      'puavo_request_id' => request_id,
    }

    # TODO: Validate the caller and generate a suitable access token for it.

    headers['Cache-Control'] = 'no-store'
    headers['Pragma'] = 'no-cache'

    json(out)
  end

  # Handles a "authorization_code" request. See RFC 6479 section 4.1.3.
  def handle_authorization_code
    temp_request_id = make_request_id

    # ----------------------------------------------------------------------------------------------
    # Retrive the code and the current state

    begin
      code = params.fetch('code', nil)
      oidc_state = _oidc_redis.get(code)
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

    begin
      oidc_state = JSON.parse(oidc_state)
    rescue StandardError => e
      rlog.error("[#{temp_request_id}] Unable to parse the JSON in OIDC state \"#{code}\"")
      return json_error('server_error', request_id: temp_request_id)
    end

    state = oidc_state['state'].freeze

    request_id = oidc_state['request_id']
    rlog.info("[#{request_id}] OIDC stage 3 token generation for state \"#{code}\"")

    # ----------------------------------------------------------------------------------------------
    # Verify the redirect URI

    # This has to be the same address where the response was sent at the end of stage 2.
    # RFC 6749 says this is optional, but we require it.
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
      client_config = YAML.safe_load(File.read('/etc/puavo-web/oidc.yml'))
    rescue StandardError => e
      rlog.error("[#{request_id}] Can't parse the OIDC configuration file: #{e}")
      return json_error('server_error', state: state, request_id: request_id)
    end

    # Assume this does not fail, since we've validated everything
    client_config = client_config['clients'][client_id].freeze

    # ----------------------------------------------------------------------------------------------
    # Verify the scopes

    # TODO: If scopes are specified, they must be compared against the scopes that were
    # specified in the original authorization request. The scopes must be identical or
    # a subset. If they include new scopes, the request must be rejected.

    # TODO: I don't know what to do with the new scopes. Do we use them below, or do we
    # use the original scopes? I don't know. I can't find any specifications for this,
    # nor any examples. RFC 6749 simply mentions it's possible to specify the scopes
    # again this call.

    # ----------------------------------------------------------------------------------------------
    # All good. Build the ID token, stash it in a JWT and return.

    # Prevent code reuse
    _oidc_redis.del(code)

    expires_in = 3600
    now = Time.now.utc.to_i

    payload = {
      'iss' => 'https://auth.opinsys.fi',
      'jti' => SecureRandom.uuid,
      'sub' => oidc_state['user']['uuid'],
      'aud' => oidc_state['client_id'],
      'iat' => now,
      'exp' => now + expires_in,
      'auth_time' => oidc_state['auth_time'],
    }

    if oidc_state.include?('nonce')
      payload['nonce'] = oidc_state['nonce']
    end

    # Collect the user data and append it to the payload
    organisation = Organisation.by_domain(oidc_state['organisation']['domain'])
    LdapModel.setup(organisation: organisation, credentials: CONFIG['server'])

    user = PuavoRest::User.by_dn(oidc_state['user']['dn'])

    if user.nil?
      rlog.error("[#{request_id}] Cannot find the logged-in user (DN=#{oidc_state['user']['dn']})")
      return json_error('access_denied', state: state, request_id: request_id)
    end

    if user.locked || user.removal_request_time
      rlog.error("[#{request_id}] The target user (#{user.username}) is locked or marked for deletion")
      return json_error('access_denied', state: state, request_id: request_id)
    end

    payload.merge!(gather_user_data(request_id, oidc_state['scopes'], organisation, user))

    # The client has to supply this token in future requests to other OIDC endpoints
    #access_token = SecureRandom.hex(16)

    out = {
      'access_token' => nil, #access_token,
      'token_type' => 'Bearer',
      'expires_in' => expires_in,
      'id_token' => JWT.encode(payload, external_service.secret, 'HS256'),
      'puavo_request_id' => request_id,
    }

    if oidc_state['scopes_changed']
      # RFC 6749 section 3.3. says the scopes must be included in the response if
      # it is different from the scopes the client specified. The spec is unclear
      # how the scopes should be encoded (array or list). Return them in the way
      # they are specified in the request.
      out['scopes'] = oidc_state['scopes'].join(' ')
    end

    # TODO: The access token must be stored in Redis

    headers['Cache-Control'] = 'no-store'
    headers['Pragma'] = 'no-cache'

    json(out)
  end

  # OpenID Connect SSO session logout
  get '/oidc/authorize/logout' do
    session_try_logout
  end

private

  def _oidc_redis
    Redis::Namespace.new('oidc_session', redis: REDIS_CONNECTION)
  end

  # Parses a string containing scopes separated by spaces, and removes the scopes that
  # aren't allowed for this client and also the invalid scopes.
  def clean_scopes(raw_scopes, oidc_config, client_config, request_id)
    rlog.info("[#{request_id}] Raw incoming scopes: #{raw_scopes.inspect}")
    scopes = raw_scopes.split(' ').to_set

    unless scopes.include?('openid')
      rlog.error("[#{request_id}] No 'openid' found in scopes")
      return { success: false }
    end

    original = scopes.dup

    # Remove scopes that aren't allowed for this client
    client_allowed = (['openid'] + client_config.fetch('allowed_scopes', [])).to_set
    scopes &= client_allowed

    # Remove unknown scopes
    scopes &= BUILTIN_SCOPES
    rlog.info("[#{request_id}] Final cleaned-up scopes: #{scopes.to_a.inspect}")

    {
      success: true,
      scopes: scopes.to_a,
      changed: scopes != original       # need to inform the client about changed scopes
    }
  rescue StandardError => e
    rlog.info("[#{request_id}] Could not clean up the scopes: #{e}")
    { success: false }
  end

  # RFC 6749 section 4.1.2.1.
  def redirect_error(redirect_uri, http_status, error, error_description: nil, error_uri: nil, state: nil, request_id: nil)
    out = {}

    out['error'] = error
    out['error_description'] = error_description if error_description
    out['error_uri'] = error_uri if error_uri
    out['state'] = state if state
    out['puavo_request_id'] = request_id if request_id

    uri = URI(redirect_uri)
    uri.query = URI.encode_www_form(out)

    redirect uri
  end

  # RFC 6749 section 5.2.
  def json_error(error, http_status: 400, error_description: nil, error_uri: nil, state: nil, request_id: nil)
    out = {}

    out['error'] = error
    out['error_description'] = error_description if error_description
    out['error_uri'] = error_uri if error_uri
    out['state'] = state if state
    out['puavo_request_id'] = request_id if request_id

    headers['Cache-Control'] = 'no-store'
    headers['Pragma'] = 'no-cache'

    return http_status, json(out)
  rescue StandardError => e
    puts e
  end

  def get_external_service(dn)
    LdapModel.setup(credentials: CONFIG['server']) do
      PuavoRest::ExternalService.by_dn(dn)
    end
  end

  # School searches are slow, so cache them
  def get_school(dn, cache)
    unless cache.include?(dn)
      cache[dn] = School.by_dn(dn)
    end

    cache[dn]
  end

  def gather_user_data(request_id, scopes, organisation, user)
    out = {}
    school_cache = {}

    if scopes.include?('profile')
      # Try to extract the modification timestamp from the LDAP operational attributes
      begin
        extra = User.raw_filter("ou=People,#{organisation['base']}", "(puavoId=#{user.id})", ['modifyTimestamp'])
        updated_at = Time.parse(extra[0]['modifyTimestamp'][0]).to_i
      rescue StandardError => e
        rlog.warn("[#{request_id}] Cannot determine the user's last modification time: #{e}")
        updated_at = nil
      end
    end

    # Include LDAP DNs in the response?
    has_ldap = scopes.include?('ldap')

    if scopes.include?('profile')
      out['given_name'] = user.first_name
      out['family_name'] = user.last_name
      out['name'] = "#{user.first_name} #{user.last_name}"
      out['preferred_username'] = user.username
      out['uuid'] = user.uuid
      out['puavoid'] = user.puavo_id.to_i
      out['ldap_dn'] = user.dn if has_ldap
      out['external_id'] = user.external_id if user.external_id
      out['learner_id'] = user.learner_id if user.learner_id
      out['roles'] = user.roles
      out['updated_at'] = updated_at unless updated_at.nil?
      out['locale'] = user.locale
      out['timezone'] = user.timezone
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
            out['email_verified'] = false
          else
            out['email'] = nil
            out['email_verified'] = false
          end
        end
      end
    end

    if scopes.include?('phone')
      out['phone_number'] = user.telephone_number[0] unless user.telephone_number.empty?
    end

    if scopes.include?('schools')
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
          'primary' => user.primary_school_dn == s.dn,
        }

        school['ldap_dn'] = s.dn if has_ldap

        schools << school
      end

      out['schools'] = schools
    end

    if scopes.include?('groups')
      have_schools = scopes.include?('schools')
      groups = []

      user.groups.each do |g|
        group = {
          'name' => g.name,
          'abbreviation' => g.abbreviation,
          'puavoid' => g.id.to_i,
          'external_id' => g.external_id,
          'type' => g.type,
        }

        group['ldap_dn'] = g.dn if has_ldap
        group['school_id'] = get_school(g.school_dn, school_cache).puavo_id.to_i if have_schools

        groups << group
      end

      out['groups'] = groups
    end

    if scopes.include?('organisation')
      org = {
        'name' => organisation.name,
        'domain' => organisation.domain,
      }

      org['ldap_dn'] = organisation.dn if has_ldap

      out['organisation'] = org
    end

    if scopes.include?('admins')
      out['is_organisation_owner'] = organisation.owner.include?(user.dn)

      if scopes.include?('schools')
        out['admin_in_schools'] = user.admin_of_school_dns.collect do |dn|
          get_school(dn, school_cache).abbreviation
        end
      end
    end

    if scopes.include?('security')
      out['mfa_enabled'] = user.mfa_enabled == true
      out['opinsys_admin'] = nil    # TODO: Future placeholder (for now)
    end

    school_cache = nil
    out
  end

end   # class OpenIDConnect

end   # module PuavoRest
