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

    # Check for expired accounts
    if user && user.account_expiration_time && Time.now.utc >= Time.at(user.account_expiration_time)
      return sso_render_form(request_id, error_message: t.sso.expired_account, exception: err)
    end

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
          type: 'jwt',

          # Needed to validate the code and do the redirect
          request_id: request_id,
          user_uuid: user.uuid,
          user_hash: user_hash,
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
