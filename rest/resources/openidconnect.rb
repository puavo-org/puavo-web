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
  roles
  organisation
  schools
  groups
  admin
  ldap
  security
).to_set.freeze

class OpenIDConnect < PuavoSinatra
  register Sinatra::R18n

  include PuavoLoginUtility

  # ------------------------------------------------------------------------------------------------
  # Stage 1: Verify the initial request parameters and authenticate the user

  # Accept both GET and POST stage 1 authorization calls
  get '/oidc/authorize' do
    oidc_stage1_authorization
  end

  post '/oidc/authorize' do
    oidc_stage1_authorization
  end

  def oidc_stage1_authorization
    request_id = make_request_id

    $rest_log.info("[#{request_id}] New OpenID Connect authentication request")

    # ----------------------------------------------------------------------------------------------
    # Check the response type

    response_type = params.fetch('response_type', nil)

    unless response_type == 'code'
      $rest_log.error("[#{request_id}] Unknown response type \"#{response_type}\", don't know how to handle it")
      status 400
      return
    end

    # ----------------------------------------------------------------------------------------------
    # (Re)Load the OpenID Connect configuration file

    begin
      oidc_config = YAML.safe_load(File.read('/etc/puavo-web/oidc.yml')).freeze
    rescue StandardError => e
      $rest_log.error("[#{request_id}] Can't parse the OIDC configuration file: #{e}")
      status 500
      return
    end

    # ----------------------------------------------------------------------------------------------
    # Verify the client ID and the target external service

    client_id = params.fetch('client_id', nil)

    $rest_log.info("[#{request_id}] client_id=\"#{client_id}\"")

    unless oidc_config['clients'].include?(client_id)
      $rest_log.error("[#{request_id}] Unknown/invalid client")
      status 403
      return
    end

    client_config = oidc_config['clients'][client_id].freeze

    # Find the target service
    service_dn = client_config['puavo_service']
    external_service = get_external_service(service_dn)

    if external_service.nil?
      $rest_log.error("[#{request_id}] Cannot find the external service by DN \"#{service_dn}\"")
      status 403
      return
    end

    # ----------------------------------------------------------------------------------------------
    # Verify the redirect URL(s)

    redirect_uri = params['redirect_uri']

    # TODO: Use longest prefix search, not full string matching
    if client_config.fetch('allowed_redirect_uris', []).find { |uri| uri == redirect_uri }.nil?
      $rest_log.error("[#{request_id}] Redirect URI \"#{redirect_uri}\" is not allowed")
      status 403
      return
    end

    # ----------------------------------------------------------------------------------------------
    # Verify the scopes

    scopes = params.fetch('scope', '').split(' ').to_set

    unless scopes.include?('openid')
      $rest_log.error("[#{request_id}] No 'openid' found in scopes (#{scopes.inspect})")
      status 400
      return
    end

    # Build a set of all scopes this client is allowed to access. If the list contains scopes
    # that aren't built-in or scope aliases, the operation stops, because this list MUST contain
    # only valid scopes.
    scope_aliases = oidc_config.fetch('scope_aliases', {}).freeze
    client_allowed = ['openid']

    client_config.fetch('allowed_scopes', []).each do |scope|
      if BUILTIN_SCOPES.include?(scope)
        client_allowed << scope
        next
      end

      if scope_aliases.include?(scope)
        client_allowed << scope_aliases[scope]
        next
      end

      $rest_log.error("[#{request_id}] Client \"#{client_id}\" has an invalid allowed scope \"#{scope}\"; it is neither a built-in scope nor a scope alias.")
      status 400
      return
    end

    client_allowed = client_allowed.flatten.to_set & BUILTIN_SCOPES

    # Remove scopes that aren't allowed. Because aliases have been expanded, their names can be
    # safely removed from the list.
    scopes = (scopes & client_allowed).to_a

    # ----------------------------------------------------------------------------------------------
    # Build Redis data

    # This structure tracks the user's whole OpenID Connect session. It is separate from the
    # "login session" that exists during the login form (and the MFA form, if enabled).
    # It persists in Redis for as long as the user stays logged in.
    oidc_state = {
      'request_id' => request_id,
      'client_id' => client_id,
      'redirect_uri' => redirect_uri,
      'scopes' => scopes,
      'state' => params.fetch('state', nil),

      # These will be copied from the login session once it completes
      'service' => nil,
      'organisation' => nil,
      'user' => nil,
    }

    if params.include?('nonce')
      oidc_state['nonce'] = params['nonce']
    end

    login_key = SecureRandom.hex(8)

    begin
      # Use the same request ID for everything
      login_data = login_create_data(request_id, external_service, is_trusted: false, next_stage: '/oidc/stage2')

      # Will be moved elsewhere once the login completes
      login_data['oidc_state'] = oidc_state

      _login_redis.set(login_key, login_data.to_json, nx: true, ex: 60 * 2)
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
  # Stage 2: Generate the return value for stage 1

  get '/oidc/stage2' do
    login_key = params.fetch('login_key', '')
    login_data = login_get_data(login_key)
    request_id = login_data['request_id']
    rlog.info("[#{request_id}] OpenID Connect login stage 2 init")

    # Copy the OpenID Connect session state from the login data,
    # and delete the login session from Redis
    oidc_state = login_data['oidc_state']
    oidc_state['service'] = login_data['service']
    oidc_state['organisation'] = login_data['organisation']
    oidc_state['user'] = login_data['user']
    _login_redis.del(login_key)

    # Optional
    oidc_state['auth_time'] = Time.now.utc.to_i

    # Generate the session code and stash everything in Redis
    code = SecureRandom.hex(8)
    _oidc_redis.set(code, oidc_state.to_json, nx: true) #, ex: 10 * 60)
    rlog.info("[#{request_id}] Generated OIDC session #{code}")

    # Return to the caller
    redirect_uri = URI(oidc_state['redirect_uri'])

    redirect_uri.query = URI.encode_www_form({
      'code' => code,
      'state' => oidc_state['state']
    })

    redirect redirect_uri
  end

  # ------------------------------------------------------------------------------------------------
  # Stage 3: Token generation and the initial JWT generation

  post '/oidc/token' do
    # ----------------------------------------------------------------------------------------------
    # Retrive the code and the current state

    code = params.fetch('code', nil)
    oidc_state = _oidc_redis.get(code)

    if oidc_state.nil?
      $rest_log.error("[???] No OpenID Connect state found by code \"#{code}\"")
      status 400
      return
    end

    begin
      oidc_state = JSON.parse(oidc_state)
    rescue StandardError => e
      $rest_log.error("[???] Unable to parse the JSON in OIDC state \"#{code}\"")
      status 400
      return
    end

    request_id = oidc_state['request_id']
    $rest_log.info("[#{request_id}] OIDC stage 3 token generation for state \"#{code}\"")

    # ----------------------------------------------------------------------------------------------
    # Verify the grant type

    grant_type = params.fetch('grant_type', nil)

    unless grant_type == 'authorization_code'
      $rest_log.error("[#{request_id}] Grant type of \"#{grant_type}\" is not supported")
      status 400
      return
    end

    # ----------------------------------------------------------------------------------------------
    # Verify the client ID

    client_id = params.fetch('client_id', nil)

    unless client_id == oidc_state['client_id']
      $rest_log.error("[#{request_id}] The client ID has changed: got \"#{client_id}\", expected \"#{oidc_state['client_id']}\"")
      status 400
      return
    end

    # ----------------------------------------------------------------------------------------------
    # Verify the client secret

    external_service = get_external_service(oidc_state['service']['dn'])
    client_secret = params.fetch('client_secret', nil)

    unless client_secret == external_service.secret
      $rest_log.error("[#{request_id}] Invalid client secret in the request")
      status 400
      return
    end

    # ----------------------------------------------------------------------------------------------
    # Verify the redirect URI

    # This has to be the same address where the response was sent at the end of stage 2
    redirect_uri = params.fetch('redirect_uri', nil)

    unless redirect_uri == oidc_state['redirect_uri']
      $rest_log.error("[#{request_id}] Mismatching redirect URIs: got \"#{redirect_uri}\", expected \"#{oidc_state['redirect_uri']}\"")
      status 400
      return
    end

    # ----------------------------------------------------------------------------------------------
    # (Re)Load the OIDC configuration

    begin
      client_config = YAML.safe_load(File.read('/etc/puavo-web/oidc.yml'))
    rescue StandardError => e
      $rest_log.error("[#{request_id}] Can't parse the OIDC configuration file: #{e}")
      status 500
      return
    end

    # Assume this does not fail, since we've validated everything
    client_config = client_config['clients'][client_id].freeze

    # ----------------------------------------------------------------------------------------------
    # All good. Build and return the JWT token.

    # TODO: Should this be configurable as per-service?
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

    payload.merge!(gather_user_data(request_id, oidc_state['scopes'], organisation, user))

    # The client has to supply this token in future requests to other OIDC endpoints
    access_token = SecureRandom.hex(16)

    out = {
      'access_token' => access_token,
      'token_type' => 'Bearer',
      'expires_in' => expires_in,
      'id_token' => JWT.encode(payload, external_service.secret, 'HS256'),
    }

    # TODO: The access token must be stored in Redis

    headers['Cache-Control'] = 'no-store'
    json(out)
  end

private

  def _oidc_redis
    Redis::Namespace.new('oidc_session', redis: REDIS_CONNECTION)
  end

  def get_external_service(dn)
    LdapModel.setup(credentials: CONFIG['server']) do
      PuavoRest::ExternalService.by_dn(dn)
    end
  end

  # School searches are slow, so cache them
  def get_school(dn, cache)
    unless cache.include?(dn)
      cache[dn] = School.find(dn)
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
        $rest_log.warn("[#{request_id}] Cannot determine the user's last modification time: #{e}")
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
        out['email_verified'] = user.primary_email
      else
        unless user.verified_email.empty?
          # This should not really happen, as the first verified email is
          # also the primary email
          out['email'] = user.verified_email[0]
          out['email_verified'] = user.verified_email[0]
        else
          if user.email
            out['email'] = user.email[0]
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
        }

        school['ldap_dn'] = s.dn if has_ldap
        school['primary'] = true if user.primary_school_dn == s.dn

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

      out['admin_in_schools'] = user.admin_of_school_dns.collect do |dn|
        get_school(dn, school_cache).abbreviation
      end
    end

    if scopes.include?('security')
      out['mfa_enabled'] = user.mfa_enabled == true
      out['opinsys_admin'] = false    # TODO: Future placeholder (for now)
    end

    school_cache = nil
    out
  end

end   # class OpenIDConnect

end   # module PuavoRest