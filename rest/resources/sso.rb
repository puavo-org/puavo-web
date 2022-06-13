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

  def respond_auth
    if return_to.nil?
      raise BadInput, :user => "return_to missing"
    end

    @external_service = fetch_external_service

    if @external_service.nil?
      raise Unauthorized,
        :user => "Unknown client service #{ return_to.host }"
    end

    request_id = 'ABCDEGIJKLMOQRUWXYZ12346789'.split('').sample(10).join
    had_session = false

    if session = read_sso_session(request_id)
      # An SSO session cookie was found in the request, see if we can use it
      rlog.info("[#{request_id}] verifying the SSO cookie")

      organisation = session['organisation']
      sessions_in = ORGANISATIONS.fetch(organisation, {}).fetch('enable_sso_sessions_in', [])

      if sessions_in.include?(@external_service.domain)
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
    trusted = @external_service["trusted"]

    if not (trusted || school_allows || organisation_allows)
      return render_form(t.sso.service_not_activated)
    end

    url, user_hash =
      @external_service.generate_login_url(@external_service.filtered_user_hash(user), return_to)

    rlog.info("[#{request_id}] SSO login ok")

    # If SSO session cookies are enabled for this service in this organisation,
    # the create a new session
    domain = @external_service.domain
    org_key = user.organisation.organisation_key

    sessions_in = ORGANISATIONS.fetch(org_key, {}).fetch('enable_sso_sessions_in', [])

    if sessions_in.include?(domain) && !had_session
      expires = Time.now.utc + PUAVO_SSO_SESSION_LENGTH

      response.set_cookie(PUAVO_SSO_SESSION_KEY,
                          value: generate_sso_session(request_id, user_hash, user),
                          expires: expires)

      rlog.info("[#{request_id}] the SSO session will expire at #{Time.at(expires)}")
    else
      rlog.info("[#{request_id}] domain \"#{domain}\" is not eligible for SSO sessions in organisation \"#{org_key}\"")
    end

    rlog.info("[#{request_id}] redirecting SSO auth #{ user['username'] } (#{ user['dn'] }) to #{ url }")
    redirect url
  end

  get "/v3/sso" do
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

  post "/v3/sso" do

    if params["username"].include?("@") && params["organisation"]
      render_form(t.sso.invalid_username)
    end

    if !params["username"].include?("@") && params["organisation"].nil?
      rlog.error("SSO error: organisation missing from username: #{ params['username'] }")
      render_form(t.sso.organisation_missing)
    end

    user_org = nil

    if params["username"].include?("@")
      _, user_org = params["username"].split("@")
      if Organisation.by_domain(ensure_topdomain(user_org)).nil?
        rlog.error("SSO error: could not find organisation for domain #{ user_org }")
        render_form(t.sso.bad_username_or_pw)
      end
    end

    org = [
      user_org,
      params["organisation"],
      request.host,
    ].map do |org|
      Organisation.by_domain(ensure_topdomain(org))
    end.compact.first


    if org
      LdapModel.setup(:organisation => org)
    else
      render_form(t.sso.no_organisation)
    end

    respond_auth
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

  def generate_sso_session(request_id, user_hash, user)
    key = SecureRandom.hex(64)

    rlog.info("[#{request_id}] creating a new SSO session cookie #{key}")

    data = {
      dn: user.dn.to_s,   # not included in the JWT, but we need it for logging purposes
      organisation: user.organisation.organisation_key,   # needed when the session is restored
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
end
end
