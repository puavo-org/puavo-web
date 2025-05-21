# SSO sessions

module SSOSessions
  def _session_redis
    Redis::Namespace.new('sso_session', redis: REDIS_CONNECTION)
  end

  def session_enabled?(request_id, organisation, domains)
    begin
      ORGANISATIONS.fetch(organisation, {}).fetch('enable_sso_sessions_in', []).each do |test|
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

  def session_create(
    request_id,
    organisation,
    service_domain,
    service_dn,
    user_dn,
    user_hash,
    had_session     # does a session cookie exist already?
  )
    return if had_session

    unless session_enabled?(request_id, organisation, service_domain)
      rlog.info("[#{request_id}] domain \"#{service_domain}\" in organisation \"#{organisation}\" is not eligible for SSO sessions")
      return
    end

    rlog.info("[#{request_id}] SSO sessions are enabled for domain \"#{service_domain}\" in organisation \"#{organisation}\"")

    # This key is stored in a cookie in the user's browser. No other data is stored
    # in the cookie, to avoid leaking anything.
    session_key = SecureRandom.hex(64)
    rlog.info("[#{request_id}] creating a new SSO session cookie #{session_key}")

    # The data in Redis is not obfuscated or encrypted. Anyone who can access the production
    # Redis database (a very, very small group of people in the world) can already generate
    # the full user information anyway.
    session_data = {
      organisation: organisation,
      dn: user_dn,
      original_service: service_dn,
      user_hash: user_hash,
    }.to_json.to_s

    redis = _session_redis
    redis.set("data:#{session_key}", session_data, nx: true, ex: PUAVO_SSO_SESSION_LENGTH)

    # This is used to locate and invalidate the session if the user is edited/removed
    redis.set("user:#{user_hash['puavo_id']}", session_key, nx: true, ex: PUAVO_SSO_SESSION_LENGTH)

    expires = Time.now.utc + PUAVO_SSO_SESSION_LENGTH
    rlog.info("[#{request_id}] the SSO session will expire at #{Time.at(expires)} (in #{PUAVO_SSO_SESSION_LENGTH} seconds)")

    response.set_cookie(PUAVO_SSO_SESSION_KEY, value: session_key, expires: expires)
  rescue StandardError => e
    # TODO: Should this be displayed to the user?
    rlog.error("[#{request_id}] could not create an SSO session: #{e}")
  end

  def session_try_login(request_id, external_service)
    # ----------------------------------------------------------------------------------------------
    # If the session cookie exists, load its contents from Redis

    unless request.cookies.include?(PUAVO_SSO_SESSION_KEY)
      return [false, nil]
    end

    key = request.cookies[PUAVO_SSO_SESSION_KEY]
    rlog.info("[#{request_id}] have SSO session cookie #{key} in the request")

    redis = _session_redis
    data = redis.get("data:#{key}")

    unless data
      rlog.error("[#{request_id}] no session data found by key #{key}; it has expired or it is invalid")
      return [false, nil]
    end

    ttl = redis.ttl("data:#{key}")
    rlog.info("[#{request_id}] the SSO session will expire at #{Time.now.utc + ttl} (in #{ttl} seconds)")

    session = JSON.parse(data)

    # ----------------------------------------------------------------------------------------------
    # Process the session data

    rlog.info("[#{request_id}] verifying the SSO cookie")
    organisation = session['organisation']

    unless session_enabled?(request_id, organisation, external_service.domain)
      rlog.error("[#{request_id}] SSO cookie login rejected, the target external service domain (" + \
                 @external_service.domain.inspect + ") is not on the list of allowed services")

      # Return true here to avoid creating another session (ie. "a session already exists,
      # but we won't use it this time")
      return [true, nil]
    end

    redirect_url, _ = @external_service.generate_login_url(session['user_hash'], return_to)
    rlog.info("[#{request_id}] SSO cookie login OK")
    rlog.info("[#{request_id}] redirecting SSO auth for \"#{session['user_hash']['username']}\" to #{redirect_url}")

    return [false, redirect_url]
  rescue StandardError => e
    rlog.error("[#{request_id}] SSO session login attempt failed: #{e}")
    return [false, nil]
  end

  # Remove the SSO session if it exists. Redirects the browser to the specifiec redirect URL
  # afterwards. This is intended to be used in browsers, to implement a "real" logout. If there
  # is no session, only does the redirect. The redirect URLs must be allowed in advance.
  def session_try_logout
    request_id = make_request_id

    begin
      rlog.info("[#{request_id}] new SSO logout request")

      # The redirect URL is always required. No way around it, as it's the only security
      # measure against malicious logout URLs.
      redirect_to = params.fetch('redirect_to', nil)

      if redirect_to.nil? || redirect_to.strip.empty?
        rlog.warn("[#{request_id}] no redirect_to parameter in the request")
        generic_error("Missing the redirect URL. Logout cannot be processed. Request ID: #{request_id}.")
      end

      rlog.info("[#{request_id}] the redirect URL is \"#{redirect_to}\"")

      redis = _session_redis

      # Extract session data
      if request.cookies.include?(PUAVO_SSO_SESSION_KEY)
        begin
          key = request.cookies[PUAVO_SSO_SESSION_KEY]
          rlog.info("[#{request_id}] session key is \"#{key}\"")

          data = redis.get("data:#{key}")

          unless data
            rlog.error("[#{request_id}] no session data found in Redis")
          else
            session_data = JSON.parse(data)
          end
        rescue StandardError => e
          rlog.error("[#{request_id}] cannot load session data:")
          rlog.error("[#{request_id}] #{e.backtrace.join("\n")}")
          session_data = nil
        end
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
        generic_error("The supplied redirect URL is not permitted. Logout cannot be processed for " \
                      "security reasons. Request ID: #{request_id}.")
      end

      rlog.info("[#{request_id}] the redirect URL is allowed")

      if session_data
        # TODO: Check if the service that originated the logout request is the same that created it?
        # This can potentially make logout procedures very complicated, but it would increase security.

        # Purge the session and redirect
        rlog.info("[#{request_id}] proceeding with the logout")

        key = request.cookies[PUAVO_SSO_SESSION_KEY]
        user_id = session_data['user_hash']['id']

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
    rescue StandardError => e
      rlog.error("[#{request_id}] session logout failed: #{e}")
      generic_error("System error. Sorry, but the logout cannot be processed. Request ID: #{request_id}.")
    end
  end
end
