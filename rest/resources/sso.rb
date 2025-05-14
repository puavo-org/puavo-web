require "sinatra/r18n"
require "sinatra/cookies"

require_relative "./users"

require_relative '../lib/sso/form_utility'
require_relative '../lib/sso/sessions'
require_relative '../lib/sso/mfa'

module PuavoRest

class SSO < PuavoSinatra
  register Sinatra::R18n

  include FormUtility
  include SSOSessions
  include MFA

  get '/v3/sso' do
    sso_try_login
  end

  post '/v3/sso' do
    sso_handle_form_post
  end

  get '/v3/verified_sso' do
    sso_try_login
  end

  post '/v3/verified_sso' do
    sso_handle_form_post
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
    erb :developers, layout: :layout
  end

  def sso_try_login(request_id: nil)
    # Determine the target external service
    request_id = make_request_id if request_id.nil?

    if return_to.nil?
      rlog.error("[#{request_id}] There's no 'return_to' or 'return' parameter in the request URL. Unable to determine the target external service.")
      rlog.error("[#{request_id}] Full original request URL: #{request.url.to_s.inspect}")
      generic_error(t.sso.return_to_missing(request_id), status: 400)
    end

    @external_service = fetch_external_service

    if @external_service.nil?
      rlog.error("[#{request_id}] No target external service found by return_to parameter #{return_to.to_s.inspect}")
      rlog.error("[#{request_id}] Full original request URL: #{request.url.to_s.inspect}")
      generic_error(t.sso.unknown_service(request_id))
    end

    # Verify the trusted service URL status (a trusted service must use a trusted SSO URL)
    @is_trusted = request.path == '/v3/verified_sso'

    rlog.info("[#{request_id}] attempting to log into external service \"#{@external_service.name}\" (#{@external_service.dn.to_s})")

    if @external_service.trusted != @is_trusted
      # No mix-and-matching or service types
      rlog.error("[#{request_id}] Trusted service type mismatch (service trusted=#{@external_service.trusted}, URL verified=#{@is_trusted})")
      rlog.error("[#{request_id}] Full original request URL: #{request.url.to_s.inspect}")
      generic_error(t.sso.state_mismatch(request_id))
    end

    # SSO session login?
    had_session, redirect_url = session_try_login(request_id, @external_service)
    return redirect(redirect_url) if redirect_url

    # Try to log in. Permit multiple different authentication methods.
    begin
      auth :basic_auth, :from_post, :kerberos
    rescue KerberosError => err
      # Kerberos authentication failed, present the normal login form
      return sso_render_form(request_id, error_message: t.sso.kerberos_error, exception: err)
    rescue JSONError => err
      # We get here if all the available authentication methods fail. But since the
      # 'force_error_message' parameter of sso_render_form() is false, we won't
      # display any error messages on the first time. Only after the form has been
      # submitted do the error messages become visible. A bit hacky, but it works.

      # Pass custom error headers to the response login page
      response.headers.merge!(err.headers)

      return sso_render_form(request_id, error_message: t.sso.bad_username_or_pw, exception: err)
    end

    # If we get here, the user was authenticated. Either by Kerberos, or by basic auth,
    # or they filled in the username+password form.
    user = User.current
    primary_school = user.school

    # Read organisation data manually instead of using the cached one because
    # enabled external services might be updated.
    organisation = LdapModel.setup(credentials: CONFIG["server"]) do
      Organisation.by_dn(LdapModel.organisation["dn"])
    end

    school_allows = Array(primary_school["external_services"]).
      include?(@external_service["dn"])
    organisation_allows = Array(organisation["external_services"]).
      include?(@external_service["dn"])

    if not (school_allows || organisation_allows)
      return sso_render_form(request_id, error_message: t.sso.service_not_activated)
    end

    # Block logins from users who don't have a verified email address, if the service is trusted
    if @external_service.trusted && @is_trusted
      rlog.info("[#{request_id}] this trusted service requires a verified address and we're in a verified SSO form")

      if Array(user.verified_email || []).empty?
        rlog.error("[#{request_id}] the current user does NOT have a verified address!")
        org = organisation.domain.split(".")[0]
        return sso_render_form(request_id, error_message: t.sso.verified_address_missing("https://#{org}.opinsys.fi/users/profile/edit"), force_error_message: true)
      end

      rlog.info("[#{request_id}] the user has a verified email address")
    end

    filtered_user = @external_service.filtered_user_hash(user, params['username'], params['organisation'])
    url, user_hash = @external_service.generate_login_url(filtered_user, return_to)

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
    generic_error(t.sso.system_error(request_id))
  end

  def sso_render_form(request_id, error_message: nil, exception: nil, force_error_message: false)
    if env["REQUEST_METHOD"] == "POST" || force_error_message
      @error_message = error_message

      if exception
        rlog.warn("sso error: #{error_message} (exception: #{exception.inspect})")
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

      'request_id' => request_id,
      "page_title" => t.sso.title,
      "external_service_name" => @external_service["name"],
      "service_title_override" => nil,
      "return_to" => params['return_to'] || params['return'] || nil,
      "organisation" => @organisation ? @organisation.domain : nil,
      "display_domain" => request['organisation'] ? Rack::Utils.escape_html(request['organisation']) : nil,
      "username_placeholder" => preferred_organisation ? t.sso.username : "#{ t.sso.username }@#{ t.sso.organisation }.#{ topdomain }",
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

    org_name = find_organisation_name()

    customise_form(@login_content, org_name)

    halt 401, {'Content-Type' => 'text/html'}, erb(:login_form, layout: :layout)
  rescue StandardError => e
    rlog.error("[#{request_id}] SSO form displaying failed: #{e}")
    generic_error(t.sso.system_error(request_id))
  end

  # Process the SSO username+password form post
  def sso_handle_form_post
    username     = params['username']
    password     = params['password']
    organisation = params['organisation']

    if params.include?('request_id') && !params['request_id'].nil? && !params['request_id'].strip.empty?
      request_id = params['request_id']
      rlog.info("[#{request_id}] Processing the submitted SSO form (resuming known login flow)")
    else
      request_id = make_request_id
      rlog.info("[#{request_id}] Processing the submitted SSO form (no request_id in the submission)")
    end

    # Determine the target organisation
    if username.include?('@') && organisation
      # This can be happen if the organisation name is pre-set in the custom URL parameters
      # ("&organisation=foo"), and the username still contains a domain name. The form contains
      # JavaScript code that removes the domain if it's known, but the form can be submitted
      # without JavaScript enabled.
      parts = username.split('@')

      rlog.info("[#{request_id}] The submitted username contains a domain (#{username.inspect}), but we already know what the organisation is (#{organisation.inspect})")

      if parts[1] == organisation
        # The specified organisation is exactly same as the domain in the username. Just strip
        # out the domain from the name and move on without an error message.
        rlog.info("[#{request_id}] It's the same organisation, moving on")
        username = parts[0]
      else
        rlog.error("[#{request_id}] The domains are different")
        sso_render_form(request_id, error_message: t.sso.invalid_username)
      end
    end

    if !username.include?('@') && organisation.nil? then
      rlog.error("[#{request_id}] SSO error: organisation missing from username: #{ username }")
      sso_render_form(request_id, error_message: t.sso.organisation_missing)
    end

    user_org = nil

    if username.include?('@') then
      username, user_org = username.split('@')

      if Organisation.by_domain(ensure_topdomain(user_org)).nil? then
        rlog.error("[#{request_id}] SSO error: could not find organisation for domain #{ user_org }")
        sso_render_form(request_id, error_message: t.sso.bad_username_or_pw)
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
        rlog.error("[#{request_id}] SSO external login error: #{ e.message }")
      end

      LdapModel.setup(organisation: org)
    else
      # No organisation found, go back to the login form
      sso_render_form(request_id, error_message: t.sso.no_organisation)
    end

    # We have a valid username, password and organisation. Try to log in again.
    sso_try_login(request_id: request_id)
  rescue StandardError => e
    rlog.error("[#{request_id}] SSO form post processing failed: #{e}")
    generic_error(t.sso.system_error(request_id))
  end

  def do_service_redirect(request_id, user_hash, url)
    rlog.info("[#{request_id}] redirecting SSO auth for \"#{ user_hash['username'] }\" to #{ url }")
    redirect url
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

end
end
