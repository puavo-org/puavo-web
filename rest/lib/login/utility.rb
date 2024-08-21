# Generic SSO login system utilities

require 'securerandom'

module PuavoLoginUtility
  def _login_redis
    Redis::Namespace.new('sso:login', redis: REDIS_CONNECTION)
  end

  def login_create_data(request_id, external_service, is_trusted: false, next_stage: nil)
    {
      'request_id' => request_id,

      'service' => {
        'dn' => external_service.dn.to_s,
        'domains' => external_service.domain,
        'trusted' => is_trusted,
      },

      'organisation' => {
        'name' => nil,
        'domain' => nil,
        'dn' => nil,
      },

      'user' => {
        'dn' => nil,
        'uuid' => nil,
        'puavoid' => nil,
        'username' => nil,
        'has_mfa' => nil,
      },

      'had_session' => nil,
      'return_to' => nil,
      'original_url' => nil,
      'user_agent' => nil,          # Hack for tests, not yet sure if really needed

      'next_stage' => next_stage
    }
  end

  # Retrieves the login data from Redis
  def login_get_data(login_key)
    login_data = _login_redis.get(login_key)

    if login_data.nil?
      # The key is invalid and we can't load the request ID from Redis. Make a new one.
      temp_request_id = make_request_id()

      rlog.error("[#{temp_request_id}] login_get_data(): no login data found in Redis by key \"#{login_key}\"")
      generic_error(t.sso.expired_login(temp_request_id))
    end

    JSON.parse(login_data)
  end

  # Deletes the login data from Redis
  def login_clear_data(login_key)
    _login_redis.del(login_key)
  end

  # Retrieves the destination external service
  def get_external_service(login_data)
    service_dn = login_data['service']['dn']

    service = LdapModel.setup(credentials: CONFIG['server']) do
      PuavoRest::ExternalService.by_dn(service_dn)
    end

    if service.nil?
      rlog.error("[#{login_data['request_id']}] get_external_service(): can't find external service by DN \"#{service_dn}\"")
      generic_error(t.sso.unknown_external_service(request_id), status_code: 401)
    end

    service
  end

  # Redirects the browser to the next stage handler
  def stage2(login_key, login_data)
    url = login_data['next_stage']

    rlog.info("[#{login_data['request_id']}] Redirecting to the next stage handler (#{url})")
    return redirect url + "?login_key=#{login_key}"
  end

  # Returns the HTTP headers that are common for all pages in the login system.
  # Try to prevent the browsers from caching anything (login pages, error messages, etc.)
  def common_headers
    {
      'Cache-Control' => 'no-cache, no-store, must-revalidate',
      'Expires' => '0',
      'Content-Type' => 'text/html'
    }
  end

  # Displays a generic error message page
  def generic_error(message, status_code: 400)
    # The message page uses the same layout as the login form, so we must fill in the relevant
    # parts of this hash.
    @login_content = {
      'prefix' => '/v3/login',      # make the built-in CSS work
      'error_message' => message,
      'technical_support' => t.sso.technical_support,
    }

    halt status_code, common_headers(), erb(:generic_error, layout: :layout)
  end

  # Attempts to determine the current organisation name. Needs access to the request object.
  def find_organisation_name(request_id)
    org_name = nil

    rlog.info("[#{request_id}] Trying to figure out the organisation name for this SSO request")

    if request['organisation']
      # Find the organisation that matches this request
      req_organisation = request['organisation']

      rlog.info("[#{request_id}] The request includes organisation name \"#{req_organisation}\"")

      # If external domains are specified, then try doing a reverse lookup
      # (ie. convert the external domain back into an organisation name)
      if CONFIG.include?('external_domains') then
        org_found = false
        CONFIG['external_domains'].each do |name, external_list|
          external_list.each do |external|
            if external == req_organisation then
              rlog.info("[#{request_id}] Found a reverse mapping from external domain \"#{external}\" " \
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
        rlog.info("[#{request_id}] Organisation \"#{req_organisation}\" exists, using it")
        org_name = req_organisation
      else
        # Look for LDAP host names
        ORGANISATIONS.each do |name, data|
          if data['host'] == req_organisation
            rlog.info("[#{request_id}] Found a configured organisation \"#{name}\"")
            org_name = name
            break
          end
        end
      end

      unless org_name
        rlog.warn("[#{request_id}] Did not find the request organisation \"#{req_organisation}\" in organisations.yml")
      end

    else
      rlog.warn("[#{request_id}] There is no organisation name in the request")
    end

    # No organisation? Is this a development/testing environment?
    unless org_name
      if ORGANISATIONS.include?('hogwarts')
        rlog.info("[#{request_id}] This appears to be a development environment, using hogwarts")
        org_name = 'hogwarts'
      end
    end

    rlog.info("[#{request_id}] Final organisation name is \"#{org_name}\"")
    org_name
  end

  # Applies per-organisation customisations to the content, if any
  def customise_form(request_id, content, org_name)
    # Any per-organisation login screen customisations?
    begin
      customisations = ORGANISATIONS[org_name]['login_screen']
      customisations = {} unless customisations.class == Hash
    rescue StandardError => e
      customisations = {}
    end

    return if customisations.empty?

    # Apply per-customer customisations
    rlog.info("[#{request_id}] Organisation \"#{org_name}\" has login screen customisations enabled")

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
end
