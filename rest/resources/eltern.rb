# Special puavo-eltern SSO login system

require "sinatra/r18n"

require 'net/http'

require_relative "./users"

module PuavoRest

class Eltern < PuavoSinatra
  register Sinatra::R18n

  get "/v3/eltern/sso" do
    respond_auth
  end

  post "/v3/eltern/sso" do
    request_id = make_request_id()
    user_org = nil

    rlog.info("[#{request_id}] processing Eltern SSO login attempt")
    rlog.info("[#{request_id}] username=\"#{params['username']}\"")

    if params["username"].include?("@")
      _, user_org = params["username"].split("@")

      if user_org == CONFIG['eltern']['service_domain']
        # The easy case: it's the target organisation
        rlog.info("[#{request_id}] this is the target domain, looking it up")

        if Organisation.by_domain(CONFIG['eltern']['login_domain']).nil?
          rlog.error("[#{request_id}] SSO error: could not find organisation for domain #{ user_org }")
          render_form(t.sso.bad_username_or_pw)
        end
      else
        # Validate the user against the external system
        rlog.info("[#{request_id}] this is not the target domain, trying external Eltern auth")

        eltern_response = eltern_auth(params['username'], params['password'], request_id)

        if eltern_response.nil?
          rlog.error("[#{request_id}] eltern_auth() returned nil")
          render_form("Authentication system failure. Try again in a minute. If the problem persists, contact Opinsys support and give them this code: #{request_id}.")
        end

        if eltern_response.fetch('user', nil).nil?
          rlog.info("[#{request_id}] Eltern did not return user data, maybe the username/password is invalid?")
          render_form(t.sso.bad_username_or_pw)
        end

        rlog.info("[#{request_id}] Eltern auth complete, the entered username+password is valid")

        # Find the external service and generate the JWT
        service = ExternalService.by_url(params['return_to'])

        if service.nil?
          raise Unauthorized, :user => "Unknown client service #{ params['return_to'] }"
        end

        url, _ = service.generate_login_url(eltern_response['user'], params['return_to'])

        rlog.info("[#{request_id}] redirecting SSO auth #{eltern_response['user']['username']} to #{url}")
        return redirect(url)
      end
    else
      # Single-domain only
      user_org = CONFIG['eltern']['login_domain']
      rlog.info("[#{request_id}] automatically filled in the target domain (\"#{CONFIG['eltern']['login_domain']}\")")
    end

    # The organisation is semi-hardcoded here. This system only logins to one domain.
    org = Organisation.by_domain(user_org)

    if org
      LdapModel.setup(:organisation => org)
    else
      rlog.error("[#{request_id}] can't find the target domain \"#{user_org}\"")
      render_form(t.sso.no_organisation)
    end

    respond_auth(request_id)
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

  def make_request_id
    'ABCDEGIJKLMOQRUWXYZ12346789'.split('').sample(10).join
  end

  def respond_auth(existing_request_id=nil)
    if params.fetch('return_to', nil).nil?
      raise BadInput, :user => "return_to missing"
    end

    return_to = Addressable::URI.parse(params['return_to'])
    @external_service = ExternalService.by_url(params['return_to'])

    if @external_service.nil?
      raise Unauthorized,
        :user => "Unknown client service #{ return_to.host }"
    end

    unless params.fetch('organisation', nil) == CONFIG['eltern']['service_domain']
      @login_content = { "prefix" => "/v3/login/eltern" }
      @error_message = t.eltern_sso.missing_organisation
      halt 400, { 'Content-Type' => 'text/html' }, erb(:fatal_error, :layout => :layout)
    end

    request_id = existing_request_id.nil? ? make_request_id : existing_request_id

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
    rlog.info("[#{request_id}] redirecting SSO auth #{ user['username'] } (#{ user['dn'] }) to #{ url }")
    redirect url
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

    @organisation = CONFIG['eltern']['login_domain']

    if !(browser.linux?)
      # Kerberos authentication works only on Opinsys desktops with Firefox.
      # Disable authentication negotiation on others since it  may cause
      # unwanted basic auth popups (at least Chrome & IE @ Windows).
      response.headers.delete("WWW-Authenticate")
    end

    @login_content = {
      "prefix" => "/v3/login/eltern",
      "page_title" => t.sso.title,
      "service_name" => t.eltern_sso.title,
      "header_text" => t.eltern_sso.header,
      "return_to" => params['return_to'] || nil,
      "organisation" => CONFIG['eltern']['service_domain'],
      "username_placeholder" => t.eltern_sso.username_placeholder,
      "username" => params["username"],
      "error_message" => @error_message,
      "text_password" => t.sso.password,
      "text_login" => t.sso.login,
    }

    unless params.fetch('organisation', nil) == CONFIG['eltern']['service_domain']
      @error_message = t.eltern_sso.missing_organisation
      halt 400, { 'Content-Type' => 'text/html' }, erb(:fatal_error, :layout => :layout)
    end

    halt 200, {'Content-Type' => 'text/html'}, erb(:eltern_login, :layout => :layout)
  end

  def eltern_auth(username, password, request_id)
    attempt = 1

    begin
      uri = URI.parse(CONFIG['eltern']['server'])
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true if uri.instance_of?(URI::HTTPS)

      # Don't get stuck for too long if puavo-eltern isn't responding
      http.open_timeout = 5
      http.read_timeout = 10

      post = Net::HTTP::Post.new(uri.request_uri)

      post.basic_auth(CONFIG['eltern']['auth']['username'], CONFIG['eltern']['auth']['password'])

      # This isn't a form submission
      post.add_field('Content-Type', 'application/json')

      post.body = {
        'username' => username,
        'password' => password
      }.to_json

      rlog.info("[#{request_id}] eltern_auth(): sending auth lookup to \"#{uri.to_s}\"")

      response = http.request(post)
      rlog.info("[#{request_id}] eltern_auth(): response status: #{response.code}")
      data = JSON.parse(response.body)

      if response.code != '200'
        rlog.error("[#{request_id}] eltern_auth(): error response: #{data.inspect}")
        return nil
      end

      return data
    rescue => e
      rlog.error("[#{request_id}] eltern_auth(): request failed: #{e}")

      # Retry to weed out intermittent network errors
      if attempt < 3
        rlog.info("[#{request_id}] eltern_auth(): attempt #{attempt + 1} in 1 second...")
        attempt += 1
        sleep 1
        retry
      else
        rlog.error("[#{request_id}] eltern_auth(): all attempts used, giving up")
        return nil
      end
    end
  end
end   # class Eltern

end   # module PuavoRest
