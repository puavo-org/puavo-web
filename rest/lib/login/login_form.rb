# The stage 1 SSO login: The username[@domain]+password login form.
# This stage should be shareable between all SSO types. Once complete,
# redirects the control to the service-specific stage 2 handler.

require 'securerandom'

require_relative './utility'

require 'byebug'

module PuavoLoginForm
  include PuavoLoginUtility

  # Tries to log in the current user, using whatever credentials might be present in the
  # request parameters. If that fails, presents the login form. The login form POST handler
  # calls this method again after the parameters have been re-populated (see later).
  def sso_login_user_with_request_params(login_key, login_data: nil, external_service: nil)
    login_data ||= login_get_data(login_key)
    external_service ||= get_external_service(login_data)
    request_id = login_data['request_id']

    # Try to log in
    begin
      auth :basic_auth, :from_post, :kerberos
    rescue KerberosError => e
      sso_render_login_form(login_key, external_service, error_message: t.sso.kerberos_error,
                            exception: e, login_data: login_data)
    rescue JSONError => e
      # Pass custom error headers to the response login page
      response.headers.merge!(e.headers)
      sso_render_login_form(login_key, external_service, error_message: t.sso.bad_username_or_pw,
                            exception: e, login_data: login_data)
    end

    # Success, we have a valid user
    sso_got_user(login_key, login_data, external_service)
  end

  # Renders the username+password form
  def sso_render_login_form(login_key, external_service, error_message: nil, exception: nil, force_error_message: false, login_data: nil)
    login_data ||= login_get_data(login_key)
    request_id = login_data['request_id']

    if env['REQUEST_METHOD'] == 'POST' || force_error_message
      @error_message = error_message

      if exception
        rlog.warn("[#{request_id}] SSO error: #{error_message} (exception: #{exception.inspect})")
      else
        rlog.warn("[#{request_id}] SSO error: #{error_message}")
      end
    end

    organisation = preferred_organisation()

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
      'prefix' => '/v3/login',

      'external_service_name' => external_service['name'],
      'service_title_override' => nil,
      'login_key' => login_key,
      'organisation' => organisation ? organisation.domain : nil,
      'display_domain' => request['organisation'],
      'username_placeholder' => username_placeholder(),
      'username' => params['username'],
      'error_message' => @error_message,
      'need_verified_address' => external_service.trusted,
      'topdomain' => topdomain(),

      # Translated strings and messages
      'page_title' => t.sso.title,
      'verified_address_notice' => t.sso.verified_address_notice,
      'text_password' => t.sso.password,
      'text_login' => t.sso.login,
      'text_help' => t.sso.help,
      'text_username_help' => t.sso.username_help,
      'text_organisation_help' => t.sso.organisation_help,
      'text_developers' => t.sso.developers,
      'text_developers_info' => t.sso.developers_info,
      'support_info' => t.sso.support_info,
      'text_login_to' => t.sso.login_to
    }

    # Apply customisations, if any
    org_name = find_organisation_name(request_id)
    customise_form(request_id, @login_content, org_name)

    # The halt code needs to be 401, because it's critical for Kerberos to work.
    # See the comment for method kerberos() in lib/auth.rb.
    halt 401, common_headers(), erb(:login_form, layout: :layout)
  end

  # Processes the login form POST
  def handle_login_form_post
    # Resume login session
    login_key = params['login_key']
    login_data = login_get_data(login_key)
    request_id = login_data['request_id']
    external_service = get_external_service(login_data)

    # Load form submission parameters
    username     = params['username']
    password     = params['password']
    organisation = params['organisation']

    if username.include?('@') && organisation then
      # This can be happen if the organisation name is pre-defined in the custom URL
      # parameters ("&organisation=foo"), and the username still contains a domain name.
      parts = username.split('@')

      if parts[1] == organisation
        # The specified organisation is exactly same as the domain in the username. Just strip
        # out the domain from the name and move on without an error message. The form contains
        # JavaScript code that removes the domain if it's known, but the form can be submitted
        # without JavaScript enabled.
        username = parts[0]
      else
        sso_render_login_form(login_key, external_service, error_message: t.sso.invalid_username, login_data: login_data)
      end
    end

    if !username.include?('@') && organisation.nil? then
      rlog.error("[#{request_id}] Organisation name missing from username (\"#{ username }\"), returning to the login form")
      sso_render_login_form(login_key, external_service, error_message: t.sso.organisation_missing, login_data: login_data)
    end

    user_org = nil

    if username.include?('@') then
      username, user_org = username.split('@')
      if PuavoRest::Organisation.by_domain(ensure_topdomain(user_org)).nil? then
        rlog.error("[#{request_id}] No organisation found by domain \"#{ user_org }\", returning to the login form")
        sso_render_login_form(login_key, external_service, error_message: t.sso.bad_username_or_pw, login_data: login_data)
      end
    end

    # Find the target organisation
    org = [
      user_org,
      organisation,
      request.host,
    ].map do |org|
      PuavoRest::Organisation.by_domain(ensure_topdomain(org))
    end.compact.first

    if org then
      # Try external login first.  Does nothing if external login
      # is not configured for this organisation.
      begin
        PuavoRest::ExternalLogin.auth(username, password, org, {})
      rescue StandardError => e
        rlog.error("[#{request_id}] SSO external login error: #{ e.message }")
      end

      LdapModel.setup(:organisation => org)
    else
      # No organisation found, go back to the login form
      sso_render_login_form(login_key, external_service, error_message: t.sso.no_organisation, login_data: login_data)
    end

    # If we get here, we have potentially a valid username@domain+password information in the
    # request params. Try logging in again. (Must use a new exception block. The original block
    # that was created for this is long gone by now.)
    begin
      sso_login_user_with_request_params(login_key, login_data: login_data, external_service: external_service)
    rescue StandardError => e
      rlog.error("[#{request_id}] Unhandled exception in the SSO system: #{e}")
      rlog.error("[#{request_id}] #{e.backtrace.join("\n")}")
      generic_error(t.sso.unspecified_error(request_id))
    end
  end

  # Handles the user once they have logged in. Verifies the external service,
  # and handles MFA and SSO sessions.
  def sso_got_user(login_key, login_data, external_service)
    request_id = login_data['request_id']

    user = PuavoRest::User.current
    primary_school = user.school

    # Read organisation data manually instead of using the cached one because
    # enabled external services might be updated.
    organisation = LdapModel.setup(credentials: CONFIG['server']) do
      PuavoRest::Organisation.by_dn(LdapModel.organisation['dn'])
    end

    # Is the service active?
    organisation_allows = Array(organisation['external_services']).include?(external_service['dn'])
    school_allows = Array(primary_school['external_services']).include?(external_service['dn'])

    unless organisation_allows || school_allows
      sso_render_login_form(login_key, external_service,
                            error_message: t.sso.service_not_activated,
                            login_data: login_data)
    end

    # If the service is trusted, block users who don't have a verified email address
    if external_service.trusted && login_data['service']['trusted']
      rlog.info("[#{request_id}] this trusted service requires a verified address and we're in a verified SSO form")

      if Array(user.verified_email || []).empty?
        rlog.error("[#{request_id}] the current user does NOT have a verified address!")

        # Build a link to the profile editor in the current organisation
        org = organisation.domain.split('.')[0]

        sso_render_login_form(login_key, external_service,
                              error_message: t.sso.verified_address_missing("https://#{org}.opinsys.fi/users/profile/edit"),
                              force_error_message: true, login_data: login_data)
      end

      rlog.info("[#{request_id}] the user has a verified email address")
    end

    rlog.info("[#{request_id}] SSO login OK, we have a valid user in a valid service")

    # Update the login data in Redis without resetting the TTL
    login_data['organisation']['name'] = organisation.name
    login_data['organisation']['dn'] = organisation.dn
    login_data['user']['dn'] = user.dn
    login_data['user']['uuid'] = user.uuid
    login_data['user']['puavoid'] = user.id
    login_data['user']['username'] = user.username
    login_data['user']['has_mfa'] = user.mfa_enabled == true

    _login_redis.set(login_key, login_data.to_json, keepttl: true)

    # Does the user have MFA enabled?
    unless login_data['user']['has_mfa']
      # No, just handle the session and continue to stage 2
      session_create(login_key, login_data)

      return stage2(login_key, login_data)
    end

    # Go to the MFA code form
    begin
      rlog.info("[#{request_id}] the user has MFA enabled, opening the MFA code form")

      mfa_url = URI(request.url)
      mfa_url.path = '/v3/mfa'
      mfa_url.query = "login_key=#{login_key}"

      redirect mfa_url
    rescue StandardError => e
      rlog.error("[#{request_id}] Could not initiate an MFA session: #{e}")
      rlog.error("[#{request_id}] #{e.backtrace.join("\n")}")

      login_clear_data(login_key)
      mfa_clear(login_key)

      # TODO: Maybe we could give a more specific error message here? We know it's MFA-related.
      generic_error(t.sso.unspecified_error(request_id))
    end

    # Unreachable
  end

private

  # Various helper methods for the login form

  def username_placeholder
    if preferred_organisation()
      t.sso.username
    else
      "#{ t.sso.username }@#{ t.sso.organisation }.#{ topdomain() }"
    end
  end

  def make_request_id
    'ABCDEGIJKLMOQRUWXYZ12346789'.split('').sample(10).join
  end

  def topdomain
    CONFIG['topdomain']
  end

  def ensure_topdomain(org)
    return if org.nil?

    CONFIG['external_domains']&.each do |k, e|
      if e.include?(org) then
        org = k + "." + topdomain()
        break
      end
    end

    if !org.end_with?(topdomain())
      return "#{ org }.#{ topdomain() }"
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
      PuavoRest::Organisation.by_domain(org)
    end.first
  end
end
