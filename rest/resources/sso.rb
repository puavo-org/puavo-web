require "addressable/uri"
require "sinatra/r18n"
require "sinatra/cookies"

require_relative "./users"

module PuavoRest

class SSO < PuavoSinatra
  register Sinatra::R18n

  get '/v3/sso' do
    respond_auth
  end

  post '/v3/sso' do
    do_sso_post
  end

  get '/v3/verified_sso' do
    respond_auth
  end

  post '/v3/verified_sso' do
    do_sso_post
  end

  get '/v3/sso/logout' do
    session_try_logout
  end

  get '/v3/mfa' do
    mfa_ask_code
  end

  post '/v3/mfa' do
    mfa_check_code
  end

  get '/v3/sso/developers' do
    @body = File.read('doc/SSO_DEVELOPERS.html')
    erb :developers, :layout => :layout
  end

  def return_to
    # Support "return_to" and "return"
    if params.include?('return_to')
      Addressable::URI.parse(params['return_to'])
    elsif params.include?('return')
      Addressable::URI.parse(params['return'])
    else
      nil
    end
  end

  def fetch_external_service
    # Support "return_to" and "return"
    if params.include?('return_to')
      ExternalService.by_url(params['return_to'])
    elsif params.include?('return')
      ExternalService.by_url(params['return'])
    else
      nil
    end
  end

  def username_placeholder
    if preferred_organisation
      t.sso.username
    else
      "#{ t.sso.username }@#{ t.sso.organisation }.#{ topdomain }"
    end
  end

  def make_request_id
    'ABCDEGIJKLMOQRUWXYZ12346789'.split('').sample(10).join
  end

  def generic_error(message)
    @login_content = {
      'error_message' => message,
      'technical_support' => t.sso.technical_support,
      'prefix' => '/v3/login',      # make the built-in CSS work
    }

    halt 401, { 'Content-Type' => 'text/html' }, erb(:generic_error, :layout => :layout)
  end

  def respond_auth
    if return_to.nil?
      raise BadInput, :user => "return_to missing"
    end

    @external_service = fetch_external_service

    if @external_service.nil?
      raise Unauthorized,
        :user => "Unknown client service #{ return_to.host }"
    end

    request_id = make_request_id
    @is_trusted = request.path == '/v3/verified_sso'

    rlog.info("[#{request_id}] attempting to log into external service \"#{@external_service.name}\" (#{@external_service.dn.to_s})")

    if @external_service.trusted != @is_trusted
      # No mix-and-matching or service types
      rlog.error("[#{request_id}] trusted service type mismatch (service trusted=#{@external_service.trusted}, URL verified=#{@is_trusted})")
      raise Unauthorized, user: "Mismatch between trusted service states. Please check the URL you're using to display the login form. Request ID #{request_id}."
    end

    # SSO session login?
    had_session, redirect_url = session_try_login(request_id, @external_service)
    return redirect(redirect_url) if redirect_url

    # Normal/non-session SSO login
    begin
      auth :basic_auth, :from_post, :kerberos
    rescue KerberosError => err
      return render_form(t.sso.kerberos_error, err)
    rescue JSONError => err
      # Pass custom error headers to the response login page
      response.headers.merge!(err.headers)
      return render_form(t.sso.bad_username_or_pw, err)
    end

    user = User.current
    primary_school = user.school

    # Read organisation data manually instead of using the cached one because
    # enabled external services might be updated.
    organisation = LdapModel.setup(:credentials => CONFIG["server"]) do
      Organisation.by_dn(LdapModel.organisation["dn"])
    end

    school_allows = Array(primary_school["external_services"]).
      include?(@external_service["dn"])
    organisation_allows = Array(organisation["external_services"]).
      include?(@external_service["dn"])

    if not (school_allows || organisation_allows)
      return render_form(t.sso.service_not_activated)
    end

    # Block logins from users who don't have a verified email address, if the service is trusted
    if @external_service.trusted && @is_trusted
      rlog.info("[#{request_id}] this trusted service requires a verified address and we're in a verified SSO form")

      if Array(user.verified_email || []).empty?
        rlog.error("[#{request_id}] the current user does NOT have a verified address!")
        org = organisation.domain.split(".")[0]
        return render_form(t.sso.verified_address_missing("https://#{org}.opinsys.fi/users/profile/edit"), nil, true)
      end

      rlog.info("[#{request_id}] the user has a verified email address")
    end

    filtered_user = @external_service.filtered_user_hash(user, params['username'], params['organisation'])
    url, user_hash = @external_service.generate_login_url(filtered_user, return_to)

    rlog.info("[#{request_id}] SSO login ok")

    begin
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
            # Needed to validate the code and do the redirect
            request_id: request_id,
            user_uuid: user.uuid,
            user_hash: user_hash,
            original_url: request.url.to_s,
            redirect_url: url,

            # Data for the (potential) SSO session (we don't know yet if we have to create it)
            sso_session: {
              organisation: user.organisation.organisation_key,
              service_domain: @external_service.domain,
              service_dn: @external_service.dn.to_s,
              user_dn: user.dn.to_s,
              had_session: had_session
            }
          }
        )

        # Redirect the browser to the MFA form
        mfa_url = URI(request.url)
        mfa_url.path = '/v3/mfa'
        mfa_url.query = "token=#{session_key}"

        redirect mfa_url
      else
        # Normal login
        session_create(
          request_id,
          user.organisation.organisation_key,
          @external_service.domain,
          @external_service.dn.to_s,
          user.dn.to_s,
          user_hash,
          had_session
        )

        do_service_redirect(request_id, user_hash, url)
      end
    rescue StandardError => e
      rlog.error("[#{request_id}] generic login error: #{e}")
      generic_error("Login system error. Please try again, and if the problem persists, please contact support and give them this code: #{request_id}.")
    end
  end

  def do_service_redirect(request_id, user_hash, url)
    rlog.info("[#{request_id}] redirecting SSO auth for \"#{ user_hash['username'] }\" to #{ url }")
    redirect url
  end

  def render_form(error_message, err=nil, force_error_message=false)
    if env["REQUEST_METHOD"] == "POST" || force_error_message
      @error_message = error_message

      if err
        rlog.warn("sso error: #{error_message} (err: #{err.inspect})")
      else
        rlog.warn("sso error: #{error_message}")
      end
    end

    @external_service ||= fetch_external_service
    @organisation = preferred_organisation

    if !(browser.linux?)
      # Kerberos authentication works only on Opinsys desktops with Firefox.
      # Disable authentication negotiation on others since it  may cause
      # unwanted basic auth popups (at least Chrome & IE @ Windows).
      response.headers.delete("WWW-Authenticate")
    end

    # Base content
    @login_content = {
      # "prefix" must be set, because the same form is used for puavo-web and
      # puavo-rest, but their contents (CSS, etc.) are stored in different
      # places. This key tells the form where those resources are.
      "prefix" => "/v3/login",

      "page_title" => t.sso.title,
      "external_service_name" => @external_service["name"],
      "service_title_override" => nil,
      "return_to" => params['return_to'] || params['return'] || nil,
      "organisation" => @organisation ? @organisation.domain : nil,
      "display_domain" => request["organisation"],
      "username_placeholder" => username_placeholder,
      "username" => params["username"],
      "error_message" => @error_message,
      "need_verified_address" => @external_service.trusted,
      "verified_address_notice" => t.sso.verified_address_notice,
      "topdomain" => topdomain,
      "text_password" => t.sso.password,
      "text_login" => t.sso.login,
      "text_help" => t.sso.help,
      "text_username_help" => t.sso.username_help,
      "text_organisation_help" => t.sso.organisation_help,
      "text_developers" => t.sso.developers,
      "text_developers_info" => t.sso.developers_info,
      "support_info" => t.sso.support_info,
      "text_login_to" => t.sso.login_to
    }

    org_name = nil

    rlog.info('Trying to figure out the organisation name for this SSO request')

    if request['organisation']
      # Find the organisation that matches this request
      req_organisation = request['organisation']

      rlog.info("The request includes organisation name \"#{req_organisation}\"")

      # If external domains are specified, then try doing a reverse lookup
      # (ie. convert the external domain back into an organisation name)
      if CONFIG.include?('external_domains') then
        org_found = false
        CONFIG['external_domains'].each do |name, external_list|
          external_list.each do |external|
            if external == req_organisation then
              rlog.info("Found a reverse mapping from external domain \"#{external}\" " \
                        "to \"#{name}\", using it instead")
              req_organisation = name
              org_found = true
              break
            end
          end
          break if org_found
        end
      end

      # Find the organisation
      if ORGANISATIONS.include?(req_organisation)
        # This name probably came from the reverse mapping above
        rlog.info("Organisation \"#{req_organisation}\" exists, using it")
        org_name = req_organisation
      else
        # Look for LDAP host names
        ORGANISATIONS.each do |name, data|
          if data['host'] == req_organisation
            rlog.info("Found a configured organisation \"#{name}\"")
            org_name = name
            break
          end
        end
      end

      unless org_name
        rlog.warn("Did not find the request organisation \"#{req_organisation}\" in organisations.yml")
      end

    else
      rlog.warn('There is no organisation name in the request')
    end

    # No organisation? Is this a development/testing environment?
    unless org_name
      if ORGANISATIONS.include?('hogwarts')
        rlog.info('This appears to be a development environment, using hogwarts')
        org_name = 'hogwarts'
      end
    end

    rlog.info("Final organisation name is \"#{org_name}\"")

    begin
      # Any per-organisation login screen customisations?
      customisations = ORGANISATIONS[org_name]['login_screen']
      customisations = {} unless customisations.class == Hash
    rescue StandardError => e
      customisations = {}
    end

    unless customisations.empty?
      rlog.info("Organisation \"#{org_name}\" has login screen customisations enabled")
    end

    # Apply per-customer customisations
    if customisations.include?('css')
      @login_content['css'] = customisations['css']
    end

    if customisations.include?('upper_logos')
      @login_content['upper_logos'] = customisations['upper_logos']
    end

    if customisations.include?('header_text')
      @login_content['header_text'] = customisations['header_text']
    end

    if customisations.include?('service_title_override')
      @login_content['service_title_override'] = customisations['service_title_override']
    end

    if customisations.include?('lower_logos')
      @login_content['lower_logos'] = customisations['lower_logos']
    end

    halt 401, {'Content-Type' => 'text/html'}, erb(:login_form, :layout => :layout)
  end

  def topdomain
    CONFIG["topdomain"]
  end

  def ensure_topdomain(org)
    return if org.nil?

    CONFIG['external_domains']&.each do |k, e|
      if e.include?(org) then
        org = k + "." + topdomain
        break
      end
    end

    if !org.end_with?(topdomain)
      return "#{ org }.#{ topdomain }"
    end

    org
  end

  def preferred_organisation
    [
      params["organisation"],
      request.host,
    ].compact.map do |org|
      ensure_topdomain(org)
    end.map do |org|
      Organisation.by_domain(org)
    end.first
  end

  def do_sso_post
    username     = params['username']
    password     = params['password']
    organisation = params['organisation']

    if username.include?('@') && organisation then
      render_form(t.sso.invalid_username)
    end

    if !username.include?('@') && organisation.nil? then
      rlog.error("SSO error: organisation missing from username: #{ username }")
      render_form(t.sso.organisation_missing)
    end

    user_org = nil

    if username.include?('@') then
      username, user_org = username.split('@')
      if Organisation.by_domain(ensure_topdomain(user_org)).nil? then
        rlog.error("SSO error: could not find organisation for domain #{ user_org }")
        render_form(t.sso.bad_username_or_pw)
      end
    end

    org = [
      user_org,
      organisation,
      request.host,
    ].map do |org|
      Organisation.by_domain(ensure_topdomain(org))
    end.compact.first

    if org then
      # Try external login first.  Does nothing if external login
      # is not configured for this organisation.
      begin
        ExternalLogin.auth(username, password, org, {})
      rescue StandardError => e
        rlog.error("SSO external login error: #{ e.message }")
      end

      LdapModel.setup(:organisation => org)
    else
      render_form(t.sso.no_organisation)
    end

    respond_auth
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

  private

  # ------------------------------------------------------------------------------------------------
  # MULTI-FACTOR AUTHENTICATION

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

    halt 401, { 'Content-Type' => 'text/html' }, erb(:mfa_form, :layout => :layout)
  end

  def mfa_create_session(key, uuid, data)
    # Store the data for 5 minutes. If the user does not enter their MFA code within that time,
    # the login process is invalidated.
    redis = _mfa_redis

    # I don't know how reliable Redis' transactions really are
    redis.multi do |m|
      m.set(key, data.to_json.to_s, nx: true, ex: 60 * 5)
      m.set(uuid, '0', nx: true, ex: 60 * 5)
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

  # ------------------------------------------------------------------------------------------------
  # SSO SESSIONS

  def _session_redis
    Redis::Namespace.new('sso_session', redis: REDIS_CONNECTION)
  end

  def session_enabled?(request_id, organisation, domains)
    begin
      ORGANISATIONS.fetch(organisation, {}).fetch('enable_sso_sessions_in', []).each do |test|
        next if test.nil? || test.empty?

        if test[0] == '^'
          # A regexp domain
          re = Regexp.new(test).freeze
          return true if domains.any? { |d| re.match?(d) }
        else
          # A plain text domain
          return true if domains.include?(test)
        end
      end
    rescue => e
      rlog.error("[#{request_id}] domain matching failed: #{e}")
    end

    return false
  end

  def session_create(
    request_id,
    organisation,
    service_domain,
    service_dn,
    user_dn,
    user_hash,
    had_session     # does a session cookie exist already?
  )
    return if had_session

    unless session_enabled?(request_id, organisation, service_domain)
      rlog.info("[#{request_id}] domain \"#{service_domain}\" in organisation \"#{organisation}\" is not eligible for SSO sessions")
      return
    end

    rlog.info("[#{request_id}] SSO sessions are enabled for domain \"#{service_domain}\" in organisation \"#{organisation}\"")

    # This key is stored in a cookie in the user's browser. No other data is stored
    # in the cookie, to avoid leaking anything.
    session_key = SecureRandom.hex(64)
    rlog.info("[#{request_id}] creating a new SSO session cookie #{session_key}")

    # The data in Redis is not obfuscated or encrypted. Anyone who can access the production
    # Redis database (a very, very small group of people in the world) can already generate
    # the full user information anyway.
    session_data = {
      organisation: organisation,
      dn: user_dn,
      original_service: service_dn,
      user_hash: user_hash,
    }.to_json.to_s

    redis = _session_redis
    redis.set("data:#{session_key}", session_data, nx: true, ex: PUAVO_SSO_SESSION_LENGTH)

    # This is used to locate and invalidate the session if the user is edited/removed
    redis.set("user:#{user_hash['puavo_id']}", session_key, nx: true, ex: PUAVO_SSO_SESSION_LENGTH)

    expires = Time.now.utc + PUAVO_SSO_SESSION_LENGTH
    rlog.info("[#{request_id}] the SSO session will expire at #{Time.at(expires)} (in #{PUAVO_SSO_SESSION_LENGTH} seconds)")

    response.set_cookie(PUAVO_SSO_SESSION_KEY, value: session_key, expires: expires)
  rescue StandardError => e
    # TODO: Should this be displayed to the user?
    rlog.error("[#{request_id}] could not create an SSO session: #{e}")
  end

  def session_try_login(request_id, external_service)
    # ----------------------------------------------------------------------------------------------
    # If the session cookie exists, load its contents from Redis

    unless request.cookies.include?(PUAVO_SSO_SESSION_KEY)
      return [false, nil]
    end

    key = request.cookies[PUAVO_SSO_SESSION_KEY]
    rlog.info("[#{request_id}] have SSO session cookie #{key} in the request")

    redis = _session_redis
    data = redis.get("data:#{key}")

    unless data
      rlog.error("[#{request_id}] no session data found by key #{key}; it has expired or it is invalid")
      return [false, nil]
    end

    ttl = redis.ttl("data:#{key}")
    rlog.info("[#{request_id}] the SSO session will expire at #{Time.now.utc + ttl} (in #{ttl} seconds)")

    session = JSON.parse(data)

    # ----------------------------------------------------------------------------------------------
    # Process the session data

    rlog.info("[#{request_id}] verifying the SSO cookie")
    organisation = session['organisation']

    unless session_enabled?(request_id, organisation, external_service.domain)
      rlog.error("[#{request_id}] SSO cookie login rejected, the target external service domain (" + \
                 @external_service.domain.inspect + ") is not on the list of allowed services")

      # Return true here to avoid creating another session (ie. "a session already exists,
      # but we won't use it this time")
      return [true, nil]
    end

    redirect_url, _ = @external_service.generate_login_url(session['user_hash'], return_to)
    rlog.info("[#{request_id}] SSO cookie login OK")
    rlog.info("[#{request_id}] redirecting SSO auth for \"#{session['user_hash']['username']}\" to #{redirect_url}")

    return [false, redirect_url]
  rescue StandardError => e
    rlog.error("[#{request_id}] SSO session login attempt failed: #{e}")
    return [false, nil]
  end

  # Remove the SSO session if it exists. Redirects the browser to the specifiec redirect URL
  # afterwards. This is intended to be used in browsers, to implement a "real" logout. If there
  # is no session, only does the redirect. The redirect URLs must be allowed in advance.
  def session_try_logout
    request_id = make_request_id

    begin
      rlog.info("[#{request_id}] new SSO logout request")

      # The redirect URL is always required. No way around it, as it's the only security
      # measure against malicious logout URLs.
      redirect_to = params.fetch('redirect_to', nil)

      if redirect_to.nil? || redirect_to.strip.empty?
        rlog.warn("[#{request_id}] no redirect_to parameter in the request")
        generic_error("Missing the redirect URL. Logout cannot be processed. Request ID: #{request_id}.")
      end

      rlog.info("[#{request_id}] the redirect URL is \"#{redirect_to}\"")

      redis = _session_redis

      # Extract session data
      if request.cookies.include?(PUAVO_SSO_SESSION_KEY)
        begin
          key = request.cookies[PUAVO_SSO_SESSION_KEY]
          rlog.info("[#{request_id}] session key is \"#{key}\"")

          data = redis.get("data:#{key}")

          unless data
            rlog.error("[#{request_id}] no session data found in Redis")
          else
            session_data = JSON.parse(data)
          end
        rescue StandardError => e
          rlog.error("[#{request_id}] cannot load session data:")
          rlog.error("[#{request_id}] #{e.backtrace.join("\n")}")
          session_data = nil
        end
      else
        rlog.warn("[#{request_id}] no session cookie in the request")
      end

      # Which redirect URLs are allowed? If there is a session, use the URLs allowed for the organisation.
      # Otherwise allow all the URLs in all organisations.
      if session_data
        organisation = session_data['organisation']
        rlog.info("[#{request_id}] organisation is \"#{organisation}\"")

        allowed_redirects = ORGANISATIONS.fetch(organisation, {}).fetch('accepted_sso_logout_urls', [])
      else
        allowed_redirects = ORGANISATIONS.collect do |_, org|
          org.fetch('accepted_sso_logout_urls', [])
        end.flatten
      end

      allowed_redirects = allowed_redirects.to_set
      rlog.info("[#{request_id}] have #{allowed_redirects.count} allowed redirect URLs")

      match = allowed_redirects.find { |test| Regexp.new(test).match?(redirect_to) }

      unless match
        rlog.error("[#{request_id}] the redirect URL is not permitted")
        generic_error("The supplied redirect URL is not permitted. Logout cannot be processed for " \
                      "security reasons. Request ID: #{request_id}.")
      end

      rlog.info("[#{request_id}] the redirect URL is allowed")

      if session_data
        # TODO: Check if the service that originated the logout request is the same that created it?
        # This can potentially make logout procedures very complicated, but it would increase security.

        # Purge the session and redirect
        rlog.info("[#{request_id}] proceeding with the logout")

        key = request.cookies[PUAVO_SSO_SESSION_KEY]
        user_id = session_data['user_hash']['id']

        if redis.get("data:#{key}")
          redis.del("data:#{key}")
        end

        if redis.get("user:#{user_id}")
          redis.del("user:#{user_id}")
        end

        rlog.info("[#{request_id}] logout complete, redirecting the browser")
      else
        rlog.info("[#{request_id}] logout not done, redirecting the browser")
      end

      return redirect(redirect_to)
    rescue StandardError => e
      rlog.error("[#{request_id}] session logout failed: #{e}")
      generic_error("System error. Sorry, but the logout cannot be processed. Request ID: #{request_id}.")
    end
  end
end
end
