require 'addressable/uri'

module FormUtility
  # Displays the SSO username+password login form
  def sso_render_form(request_id, error_message: nil, exception: nil, force_error_message: false, type: 'jwt', state_key: nil)
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

      'type' => type.to_s,
      'state_key' => state_key,
      'request_id' => request_id,
      "page_title" => t.sso.title,
      "external_service_name" => @external_service["name"],
      "service_title_override" => nil,
      "return_to" => return_to(),
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

    halt 401, common_headers(), erb(:login_form, layout: :layout)
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

    # Load type and the login state key
    type = params.fetch('type', 'jwt')
    state_key = params.fetch('state_key', nil)

    rlog.info("[#{request_id}] State key: #{state_key.inspect}")

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
        sso_render_form(request_id, error_message: t.sso.invalid_username, type: type, state_key: state_key)
      end
    end

    if !username.include?('@') && organisation.nil? then
      rlog.error("[#{request_id}] SSO error: organisation missing from username: #{ username }")
      sso_render_form(request_id, error_message: t.sso.organisation_missing, type: type, state_key: state_key)
    end

    user_org = nil

    if username.include?('@') then
      username, user_org = username.split('@')

      if PuavoRest::Organisation.by_domain(ensure_topdomain(user_org)).nil? then
        rlog.error("[#{request_id}] SSO error: could not find organisation for domain #{ user_org }")
        sso_render_form(request_id, error_message: t.sso.bad_username_or_pw, type: type, state_key: state_key)
      end
    end

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

      LdapModel.setup(organisation: org)
    else
      # No organisation found, go back to the login form
      sso_render_form(request_id, error_message: t.sso.no_organisation, type: type, state_key: state_key)
    end

    # We have a valid username, password and organisation. Try to log in again.
    if type == 'jwt'
      sso_try_login(request_id: request_id)
    end
  rescue StandardError => e
    rlog.error("[#{request_id}] SSO form post processing failed: #{e}")
    generic_error(t.sso.system_error(request_id))
  end

  # Attempts to determine which organisation we're in
  def find_organisation_name()
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
    org_name
  end

  # Applies per-organisation customisations to the content, if any
  def customise_form(content, org_name)
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
      content['css'] = customisations['css']
    end

    if customisations.include?('upper_logos')
      content['upper_logos'] = customisations['upper_logos']
    end

    if customisations.include?('header_text')
      content['header_text'] = customisations['header_text']
    end

    if customisations.include?('service_title_override')
      content['service_title_override'] = customisations['service_title_override']
    end

    if customisations.include?('lower_logos')
      content['lower_logos'] = customisations['lower_logos']
    end
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
    url = return_to()
    url.nil? ? nil : PuavoRest::ExternalService.by_url(url)
  end

  def generic_error(message, status: 401)
    @login_content = {
      'error_message' => message,
      'technical_support' => t.sso.technical_support,
      'prefix' => '/v3/login',      # make the built-in CSS work
    }

    halt status, common_headers(), erb(:generic_error, layout: :layout)
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
      PuavoRest::Organisation.by_domain(org)
    end.first
  end

  # Returns the HTTP headers that are common for all pages in the login system.
  # Tries to prevent browsers from caching anything (login pages, error messages, etc.)
  def common_headers
    {
      'Content-Type' => 'text/html',
      'Cache-Control' => 'no-cache, no-store, must-revalidate',
      'Expires' => '0',
    }
  end
end
