require 'addressable/uri'

module FormUtility
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

    halt status, { 'Content-Type' => 'text/html' }, erb(:generic_error, layout: :layout)
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
end
