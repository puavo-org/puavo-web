# Legacy JWT logins

require_relative './utility'

module PuavoLoginJWT
  include PuavoLoginUtility

  # Prepares a JWT login
  def jwt_initialize_login(request_id, login_key, is_trusted_url, was_oidc)
    # Retrieve the external service we're trying to login into
    if return_to.nil?
      rlog.error("[#{request_id}] there's no \"return_to\" or \"return\" in the URL (#{request.url})")
      generic_error(t.sso.jwt_missing_return_url(request_id))
    end

    external_service = fetch_external_service

    if external_service.nil?
      rlog.error("[#{request_id}] no external service could be found by domain \"#{return_to()}\"")
      generic_error(t.sso.unknown_external_service(request_id), status_code: 401)
    end

    rlog.info("[#{request_id}] attempting to log into external service \"#{external_service.name}\" (#{external_service.dn.to_s}), login data Redis key=\"#{login_key}\"")

    # Handle trusted/non-trusted services
    if external_service.trusted != is_trusted_url
      # No mix-and-matching of service types. A trusted service must use a trusted login URL
      # (/v3/verified_sso), and a non-trusted must use a non-trusted URL (/v3/sso).
      rlog.error("[#{request_id}] trusted service type mismatch (service trusted=#{external_service.trusted}, URL verified=#{is_trusted_url})")
      generic_error(t.sso.trusted_state_mismatch(request_id))
    end

    login_data = login_create_data(request_id, external_service, is_trusted: is_trusted_url, next_stage: was_oidc ? '/oidc/jwt' : '/v3/sso/jwt', was_oidc: was_oidc)
    login_data['return_to'] = return_to().to_s
    login_data['original_url'] = request.url.to_s

    # Is there a session for this service?
    session = session_try_login(request_id, external_service)
    login_data['had_session'] = session[:had_session]

    if session[:had_session] && session[:redirect]
      # Restore the relevant parts of the login data from the cached data
      login_data['organisation'] = session[:data]['organisation']
      login_data['user'] = session[:data]['user']
    else
      if request.env.include?('HTTP_USER_AGENT')
        # HACK: "Smuggle" the user agent header across the redirect.
        # Needed for tests, not sure if needed in production.
        login_data['user_agent'] = request.env['HTTP_USER_AGENT']
      end
    end

    _login_redis.set(login_key, login_data.to_json, nx: true, ex: PUAVO_LOGIN_TIME)

    if session[:redirect]
      return stage2(login_key, login_data)
    end
  end

  # JWT stage 2: Generates the user info JWT and redirects the browser
  def jwt_handle_stage2
    login_key = params.fetch('login_key', '')
    login_data = login_get_data(login_key)
    request_id = login_data['request_id']
    rlog.info("[#{request_id}] JWT login stage 2 init")

    session_create(login_key, login_data, {
      'organisation' => login_data['organisation'],
      'user' => login_data['user'],
    })

    _login_redis.del(login_key)

    # "Log in"
    organisation = PuavoRest::Organisation.by_domain(login_data['organisation']['domain'])
    LdapModel.setup(organisation: organisation, credentials: CONFIG['server'])

    user = PuavoRest::User.by_dn(login_data['user']['dn'])
    external_service = PuavoRest::ExternalService.by_dn(login_data['service']['dn'])

    # Generate the JWT hash
    filtered_user = external_service.filtered_user_hash(user, login_data['user']['username'], login_data['organisation']['domain'])
    url, user_hash = external_service.generate_login_url(filtered_user, login_data['return_to'])

    rlog.info("[#{request_id}] redirecting SSO auth for \"#{ login_data['user']['username'] }\" to #{ url }")
    redirect url
  end
end
