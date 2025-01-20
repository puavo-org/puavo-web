# OAuth2 helpers

module PuavoRest
module OAuth2
  # Retrieve the OpenID Connect login session data from Redis
  def oidc_redis
    Redis::Namespace.new('oidc_session', redis: REDIS_CONNECTION)
  end

  def get_external_service(dn)
    LdapModel.setup(credentials: CONFIG['server']) do
      PuavoRest::ExternalService.by_dn(dn)
    end
  end

  # RFC 6749 section 4.1.2.1.
  def redirect_error(redirect_uri, http_status, error, error_description: nil, error_uri: nil, state: nil, request_id: nil)
    out = {}

    out['error'] = error
    out['error_description'] = error_description if error_description
    out['error_uri'] = error_uri if error_uri
    out['state'] = state if state
    out['puavo_request_id'] = request_id if request_id
    out['iss'] = ISSUER

    uri = URI(redirect_uri)
    uri.query = URI.encode_www_form(out)

    redirect uri
  end

  # RFC 6749 section 5.2.
  def json_error(error, http_status: 400, error_description: nil, error_uri: nil, state: nil, request_id: nil)
    out = {}

    out['error'] = error
    out['error_description'] = error_description if error_description
    out['error_uri'] = error_uri if error_uri
    out['state'] = state if state
    out['puavo_request_id'] = request_id if request_id
    out['iss'] = ISSUER

    headers['Cache-Control'] = 'no-store'
    headers['Pragma'] = 'no-cache'

    return http_status, json(out)
  rescue StandardError => e
    puts e
  end
end   # module OAuth2
end   # module PuavoRest
