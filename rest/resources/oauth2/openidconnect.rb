# frozen_string_literal: true

# OpenID Connect SSO system

require 'sinatra/r18n'
require 'sinatra/cookies'
require 'addressable/uri'
require 'pg'

require 'securerandom'
require 'openssl'
require 'jwt'
require 'digest'

require 'base64'
require 'argon2'

require_relative '../users'

require_relative '../../lib/sso/form_utility'
require_relative '../../lib/sso/sessions'
require_relative '../../lib/sso/mfa'
require_relative '../../lib/oauth2_audit'

require_relative './scopes'
require_relative './utility'
require_relative './userinfo'

require_relative 'access_token_request'
require_relative 'id_token'
require_relative 'client_credentials_grant'

module PuavoRest
module OAuth2

# RFC 9207 issuer identifier
ISSUER = 'https://api.opinsys.fi'

class OpenIDConnect < PuavoSinatra
  register Sinatra::R18n

  include FormUtility
  include SSOSessions
  include MFA

  include AccessTokenRequest
  include ClientCredentialsGrant
  include Userinfo

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
        # RFC 6749 section 5.2.
        # Tested
        rlog.error("[#{temp_request_id}] Unsupported grant type")
        json_error('unsupported_grant_type', request_id: temp_request_id)
    end

    # Not reached
  end

  # OpenID Connect userinfo endpoints. These are the only endpoints where the access token
  # generated during logins can be used in. See userinfo.rb
  # https://openid.net/specs/openid-connect-core-1_0.html#UserInfo says we MUST support
  # both GET and POST userinfo requests.
  get '/oidc/userinfo' do
    userinfo_request
  end

  post '/oidc/userinfo' do
    userinfo_request
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
        generic_error(t.oauth2.missing_or_invalid_required_parameter(k, request_id), status: 400)
      end

      v = params.fetch(k, '')

      if v.nil? || v.strip.empty?
        # Tested
        rlog.error("[#{request_id}] A required parameter \"#{k}\" was specified but it's empty")
        rlog.error("[#{request_id}] Request parameters: #{params.inspect}")
        generic_error(t.oauth2.missing_or_invalid_required_parameter(k, request_id), status: 400)
      end
    end

    # ----------------------------------------------------------------------------------------------
    # Verify the client ID and the target external service

    client_id = params['client_id']
    rlog.info("[#{request_id}] Client ID: #{client_id.inspect}")

    unless OAuth2.valid_client_id?(client_id)
      # Tested
      rlog.error("[#{request_id}] Malformed client ID")
      generic_error(t.oauth2.invalid_client_id(request_id), status: 400)
    end

    clients = ClientDatabase.new
    client_config = clients.get_client_by_id(request_id, client_id, :login)
    clients.close

    if client_config.nil?
      # Tested
      rlog.error("[#{request_id}] No client found by that ID")
      generic_error(t.oauth2.invalid_client_id(request_id), status: 400)
    end

    unless client_config['enabled'] == 't'
      # Tested
      rlog.error("[#{request_id}] The client exists but it has been disabled")
      generic_error(t.oauth2.invalid_client_id(request_id), status: 400)
    end

    # Find the target service
    service_dn = client_config['puavo_service_dn']
    rlog.info("[#{request_id}] Target external service DN: #{service_dn.inspect}")

    begin
      # Tested
      external_service = get_external_service(service_dn)
    rescue StandardError => e
      rlog.error("[#{request_id}] Could not get the external service: #{e}")
      generic_error(t.oauth2.invalid_client_id(request_id), status: 400)
    end

    if external_service.nil?
      # Tested
      rlog.error("[#{request_id}] No external service found by that DN")
      generic_error(t.oauth2.invalid_client_id(request_id), status: 400)
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
      generic_error(t.oauth2.invalid_redirect_uri(request_id), status: 400)
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
      redirect_error(redirect_uri, 'invalid_request', state: params.fetch('state', nil), request_id: request_id)
    end

    rlog.info("[#{request_id}] The response type is #{response_type.inspect}")

    # ----------------------------------------------------------------------------------------------
    # Verify the scopes

    scopes = Scopes.clean_scopes(request_id, params.fetch('scope', ''), Scopes::BUILTIN_LOGIN_SCOPES, client_config, require_openid: true)

    unless scopes.success
      # Tested
      redirect_error(redirect_uri, 'invalid_scope', state: params.fetch('state', nil), request_id: request_id)
    end

    # ----------------------------------------------------------------------------------------------
    # Verify state and nonce, if specified

    # If the state is specified, it must be a valid non-empty string. In the oidc_state (see below) a nil
    # "state" means it was omitted from the request, not that it was an empty string.
    if params.include?('state')
      if params['state'].nil? || params['state'].strip.empty?
        # Tested
        rlog.error("[#{request_id}] State value specified, but it is nil/empty (#{params['state'].inspect})")
        redirect_error(redirect_uri, 'invalid_request', request_id: request_id)
      else
        rlog.info("[#{request_id}] Have state #{params['state'].inspect}")
      end
    end

    if params.include?('nonce')
      if params['nonce'].nil? || params['nonce'].strip.empty?
        # Tested
        rlog.error("[#{request_id}] Nonce value specified, but it is nil/empty (#{params['nonce'].inspect})")
        redirect_error(redirect_uri, 'invalid_request', state: params.fetch('state', nil), request_id: request_id)
      else
        rlog.info("[#{request_id}] Have nonce #{params['nonce'].inspect}")
      end
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
      # remember for the ID token.
      # Tested
      oidc_state['nonce'] = params['nonce']
    end

    state_key = SecureRandom.hex(64)

    rlog.info("[#{request_id}] Initialized OpenID Connect login state #{state_key.inspect}")

    # Stash the state tracking data in Redis
    oidc_redis.set(state_key, oidc_state.to_json, nx: true, ex: PUAVO_OIDC_LOGIN_TIME)

    oidc_try_login(request_id: request_id, state_key: state_key)
  rescue StandardError => e
    # Tested (manually)
    rlog.error("[#{request_id}] #{e}")
    generic_error(t.sso.system_error(request_id), status: 400)
  end

  # 'form_params' exists only when we come from the SSO username+password form; it contains all the parameters
  # in the form submission so they can be validated
  def oidc_try_login(request_id:, state_key:, form_params: nil)
    oidc_state = oidc_redis.get(state_key)

    if oidc_state.nil?
      # Tested
      rlog.error("oidc_try_login(): nothing found in Redis by state key #{state_key.inspect}, halting")
      generic_error(t.sso.system_error(request_id), status: 400)
    end

    oidc_state = JSON.parse(oidc_state)
    request_id = oidc_state['request_id']   # resume original login flow

    if state_key && form_params
      # We have a form submission, so compare the return_to address in the hidden field with the redirect URI
      # in the stored state data. They must match.
      unless form_params['return_to'] == oidc_state['redirect_uri']
        # Tested
        purge_oidc_state(state_key)
        rlog.error("[#{request_id}] The submitted form contains different redirect URI (#{form_params['return_to'].inspect}) than in the stored state (#{oidc_state['redirect_uri'].inspect})")
        generic_error(t.sso.inconsistent_login_state(request_id), status: 400)
      end
    end

    # Determine the target external service
    if return_to.nil?
      # Tested in the SSO tests
      purge_oidc_state(state_key)
      rlog.error("[#{request_id}] There's no 'return_to' or 'return' parameter in the request URL. Unable to determine the target external service.")
      rlog.error("[#{request_id}] Full original request URL: #{request.url.to_s.inspect}")
      generic_error(t.sso.return_to_missing(request_id), status: 400)
    end

    @external_service = fetch_external_service

    if @external_service.nil?
      # Tested in the SSO tests
      purge_oidc_state(state_key)
      rlog.error("[#{request_id}] No target external service found by return_to parameter #{return_to.to_s.inspect}")
      rlog.error("[#{request_id}] Full original request URL: #{request.url.to_s.inspect}")
      generic_error(t.sso.unknown_service(request_id), status: 400)
    end

    # Verify the trusted service URL status (a trusted service must use a trusted SSO URL)
    @is_trusted = request.path == '/v3/verified_sso'

    rlog.info("[#{request_id}] attempting to log into external service \"#{@external_service.name}\" (#{@external_service.dn.to_s})")

    if @external_service.trusted != @is_trusted
      # No mix-and-matching or service types
      # (Tested in the JWT code but not in OpenID Connect code; we can assume this works too.)
      purge_oidc_state(state_key)
      rlog.error("[#{request_id}] Trusted service type mismatch (service trusted=#{@external_service.trusted}, URL verified=#{@is_trusted})")
      rlog.error("[#{request_id}] Full original request URL: #{request.url.to_s.inspect}")
      generic_error(t.sso.state_mismatch(request_id), status: 400)
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

    # If we get here, the user was authenticated. Either by Kerberos, or by basic auth,
    # or they filled in the username+password form.

    # The authentication time is optional, but we can support it easily. It is specified in
    # https://openid.net/specs/openid-connect-core-1_0.html#IDToken.
    oidc_state['auth_time'] = Time.now.utc.to_i

    user = PuavoRest::User.current
    primary_school = user.school

    # Check for expired accounts
    if user && user.account_expiration_time && Time.now.utc >= Time.at(user.account_expiration_time)
      return sso_render_form(request_id, error_message: t.sso.expired_account, exception: err, type: 'oidc', state_key: state_key)
    end

    # Figure out the 'amr' claim value
    amr = []

    case auth_method
      when 'from_post', 'basic_auth'
        amr << 'pwd'

      when 'kerberos'
        # This is a non-standard Opinsys value. RFC 8176 does not list anything usable for Kerberos (and numerous
        # internet searches have not revealed anything for it), which is kinda odd, give how widespread various
        # SSO systems are. But that also poses a philosophical dilemma: since the Kerberos ticket is granted
        # at (desktop) login, and login requires a username and password, does Kerberos then technically count
        # as "pwd"? I can find references to Kerberos in the "acr" claim values, but nothing for "amr".
        amr << 'kerberos'
    end

    # If the MFA attribute is enabled, we *will* ask for the code, so this 'amr' claim value can be set already
    amr << 'mfa' if user.mfa_enabled

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
      'amr' => amr
    }

    oidc_state['organisation'] = {
      'domain' => organisation.domain,
      'key' => organisation.organisation_key,
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
    # Tested (manually)
    purge_oidc_state(state_key)
    rlog.error("[#{request_id}] generic login error: #{e}")
    generic_error(t.sso.system_error(request_id), status: 400)
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
      if state_key.nil? || state_key.strip.empty?
        # Tested
        rlog.error("[#{temp_request_id}] oidc_authorization_response(): no state_key supplied (not in function params, not in request params)")
        generic_error(t.sso.system_error(temp_request_id), status: 400)
      end

      # Get and delete the login data from Redis
      oidc_state = oidc_redis.get(state_key)

      if oidc_state.nil?
        # I could not write a test for this, because the Redis state is checked at least once before
        # we get here. I think it's possible during Kerberos authentication to get here if the state
        # gets clobbered.
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
      oidc_state['organisation']['key'],
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
    }

    unless oidc_state['state'].nil?
      # Since the state is optional, don't propagate it if's empty
      # Tested
      query['state'] = oidc_state['state']
    end

    if oidc_state['scopes_changed']
      # RFC 6749 section 4.1.2. does not mention this at all, but section 3.3 says
      # the scopes must be included in the response if they are different from the
      # scopes the client specified. The spec is unclear how the scopes should be
      # encoded (array or list). Return them as space-delimited string, because
      # that's how they're originally specified.
      # Tested
      query['scope'] = oidc_state['scopes'].join(' ')
    end

    redirect_uri.query = URI.encode_www_form(query)

    rlog.info("[#{request_id}] Redirecting the browser to \"#{redirect_uri.to_s}\"")

    redirect redirect_uri
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

    halt redirect(uri)
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

    halt http_status, json(out)
  rescue StandardError => e
    # Tested (manually)
    $rest_log.error("[#{request_id || '??????????'}] json_error(): could not format the error return: #{e}")
    halt 500, "fatal server error, please contact support and give them this message, including this code: #{request_id.inspect}"
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
