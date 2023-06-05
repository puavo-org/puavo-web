require "addressable/uri"
require "sinatra/r18n"
require "sinatra/cookies"

require_relative "./users"

module PuavoRest

class SSO < PuavoSinatra
  register Sinatra::R18n

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
    had_session = false
    @is_trusted = request.path == '/v3/verified_sso'

    rlog.info("[#{request_id}] attempting to log into external service \"#{@external_service.name}\" (#{@external_service.dn.to_s})")

    if @external_service.trusted != @is_trusted
      # No mix-and-matching or service types
      rlog.error("[#{request_id}] trusted service type mismatch (service trusted=#{@external_service.trusted}, URL verified=#{@is_trusted})")
      raise Unauthorized, user: "Mismatch between trusted service states. Please check the URL you're using to display the login form. Request ID #{request_id}."
    end

    if session = read_sso_session(request_id)
      # An SSO session cookie was found in the request, see if we can use it
      rlog.info("[#{request_id}] verifying the SSO cookie")

      organisation = session['organisation']

      if are_sessions_enabled(organisation, @external_service.domain, request_id)
        # The session cookie is usable
        url, _ = @external_service.generate_login_url(session['user'], return_to)

        rlog.info("[#{request_id}] SSO cookie login OK")
        rlog.info("[#{request_id}] redirecting SSO auth #{session['user']['username']} (#{session['dn']}) to #{url}")

        return redirect url
      else
        rlog.error("[#{request_id}] SSO cookie login rejected, the target external service domain (" + \
                   @external_service.domain.inspect + ") is not on the list of allowed services")
        had_session = true
      end
    end

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
        return render_form(t.sso.verified_address_missing)
      end

      rlog.info("[#{request_id}] the user has a verified email address")
    end

    url, user_hash =
      @external_service.generate_login_url(@external_service.filtered_user_hash(user), return_to)

    rlog.info("[#{request_id}] SSO login ok")

    # If SSO session cookies are enabled for this service in this organisation,
    # the create a new session
    domain = @external_service.domain
    org_key = user.organisation.organisation_key

    if !had_session && are_sessions_enabled(org_key, domain, request_id)
      rlog.info("[#{request_id}] SSO sessions are enabled for domain \"#{domain}\" in organisation \"#{org_key}\"")

      expires = Time.now.utc + PUAVO_SSO_SESSION_LENGTH

      response.set_cookie(PUAVO_SSO_SESSION_KEY,
                          value: generate_sso_session(request_id, user_hash, user, @external_service),
                          expires: expires)

      rlog.info("[#{request_id}] the SSO session will expire at #{Time.at(expires)}")
    else
      rlog.info("[#{request_id}] domain \"#{domain}\" is not eligible for SSO sessions in organisation \"#{org_key}\"")
    end

    rlog.info("[#{request_id}] redirecting SSO auth #{ user['username'] } (#{ user['dn'] }) to #{ url }")
    redirect url
  end

  # Remove the SSO session if it exists. Redirects the browser to the specifiec redirect URL
  # afterwards. This is intended to be used in browsers, to implement a "real" logout. If there
  # is no session, only does the redirect. The redirect URLs must be allowed in advance.
  get '/v3/sso/logout' do
    request_id = make_request_id

    rlog.info("[#{request_id}] new SSO logout request")

    # The redirect URL is always required. No way around it, as it's the only security
    # measure against malicious logout URLs.
    redirect_to = params.fetch('redirect_to', nil)

    if redirect_to.nil? || redirect_to.strip.empty?
      rlog.warn("[#{request_id}] no redirect_to parameter in the request")
      logout_error("Missing the redirect URL. Logout cannot be processed. Request ID: #{request_id}.")
    end

    rlog.info("[#{request_id}] the redirect URL is \"#{redirect_to}\"")

    redis = Redis::Namespace.new('sso_session', redis: REDIS_CONNECTION)

    # Extract session data
    if request.cookies.include?(PUAVO_SSO_SESSION_KEY)
      session_data = logout_get_session_data(request, redis, request_id)
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
      logout_error("The supplied redirect URL is not permitted. Logout cannot be processed for " \
                   "security reasons. Request ID: #{request_id}.")
    end

    rlog.info("[#{request_id}] the redirect URL is allowed")

    if session_data
      # TODO: Check if the service that originated the logout request is the same that created it?
      # This can potentially make logout procedures very complicated, but it would increase security.

      # Purge the session and redirect
      rlog.info("[#{request_id}] proceeding with the logout")

      key = request.cookies[PUAVO_SSO_SESSION_KEY]
      user_id = session_data['user']['id']

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
  end

  def logout_error(message)
    @login_content = {
      'error_message' => message,
      'prefix' => '/v3/login',      # make the built-in CSS work
    }

    halt 401, { 'Content-Type' => 'text/html' }, erb(:logout_error, :layout => :layout)
  end

  get "/v3/sso" do
    respond_auth
  end

  get '/v3/verified_sso' do
    respond_auth
  end

  def render_form(error_message, err=nil)
    if env["REQUEST_METHOD"] == "POST"
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
      if CONFIG.include?('external_domain')
        CONFIG['external_domain'].each do |name, external|
          if external == req_organisation
            rlog.info("Found a reverse mapping from external domain \"#{external}\" " \
                      "to \"#{name}\", using it instead")
            req_organisation = name
            break
          end
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

    CONFIG["external_domain"]&.each do |k, e|
      if e == org
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

  post '/v3/sso' do
    do_sso_post
  end

  post '/v3/verified_sso' do
    do_sso_post
  end

  get "/v3/sso/developers" do
    @body = File.read("doc/SSO_DEVELOPERS.html")
    erb :developers, :layout => :layout
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

  def are_sessions_enabled(organisation_key, domains, request_id)
    begin
      ORGANISATIONS.fetch(organisation_key, {}).fetch('enable_sso_sessions_in', []).each do |test|
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

  def generate_sso_session(request_id, user_hash, user, service)
    key = SecureRandom.hex(64)

    rlog.info("[#{request_id}] creating a new SSO session cookie #{key}")

    data = {
      dn: user.dn.to_s,   # not included in the JWT, but we need it for logging purposes
      organisation: user.organisation.organisation_key,   # needed when the session is restored
      original_service: service.dn.to_s,      # which external service the user is logging in to
      user: user_hash,
    }

    # The data is not obfuscated or encrypted. Anyone who can access the production
    # Redis database can also generate the full user information anyway.
    session_data = data.to_json.to_s

    redis = Redis::Namespace.new('sso_session', redis: REDIS_CONNECTION)

    redis.set("data:#{key}", session_data, nx: true, ex: PUAVO_SSO_SESSION_LENGTH)

    # This is used to locate and invalidate the session if the user is edited/removed
    redis.set("user:#{user.puavo_id}", key, nx: true, ex: PUAVO_SSO_SESSION_LENGTH)

    key
  end

  def read_sso_session(request_id)
    return nil unless request.cookies.include?(PUAVO_SSO_SESSION_KEY)

    key = request.cookies[PUAVO_SSO_SESSION_KEY]

    rlog.info("[#{request_id}] have SSO session cookie #{key} in the request")

    redis = Redis::Namespace.new('sso_session', redis: REDIS_CONNECTION)
    data = redis.get("data:#{key}")

    unless data
      rlog.error("[#{request_id}] no session data found by key #{key}; it has expired or it's invalid")
      return nil
    end

    rlog.info("[#{request_id}] session lifetime left: #{redis.ttl("data:#{key}")} seconds")

    begin
      data = JSON.parse(data)
    rescue => e
      rlog.error("[#{request_id}] have SSO session data, but it cannot be loaded: #{e}")
      return nil
    end

    data
  end

  def logout_get_session_data(request, redis, request_id)
    key = request.cookies[PUAVO_SSO_SESSION_KEY]
    rlog.info("[#{request_id}] session key is \"#{key}\"")

    data = redis.get("data:#{key}")

    unless data
      rlog.error("[#{request_id}] no session data found in Redis")
      return nil
    end

    JSON.parse(data)
  rescue StandardError => e
    rlog.error("[#{request_id}] cannot load session data:")
    rlog.error("[#{request_id}] #{e.backtrace.join("\n")}")
    nil
  end
end
end
