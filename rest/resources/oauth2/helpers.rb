# OAuth2 helpers

require 'pg'

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

  # Retrieves the client configuration from the database. 'type' must be either
  # :login or :token, depending on the client type.
  def get_client_configuration_by_id(request_id, client_id, type)
    # Fetch the entry from the database. There are two tables, one for OpenID Connect
    # login clients, and one for OAuth2 access token clients. They have some identical
    # columns, but ultimately they contain different data.
    db_config = CONFIG['oauth2']['client_database']

    db = PG.connect(hostaddr: db_config['host'],
                    port: db_config['port'],
                    dbname: db_config['database'],
                    user: db_config['user'],
                    password: db_config['password'])

    # exec_params doesn't support parameterizing the table name
    table = (type == :login) ? 'login_clients' : 'token_clients'
    rows = db.exec_params("SELECT * FROM #{table} WHERE client_id = $1;", [client_id])
    db.close

    return nil if rows.count != 1

    client_config = rows[0].to_hash

    # Convert certain columns into arrays
    array_decoder = PG::TextDecoder::Array.new

    ['allowed_redirects', 'allowed_scopes', 'allowed_endpoints', 'allowed_organisations'].each do |key|
      next unless client_config.include?(key)
      client_config[key] = array_decoder.decode(client_config[key])
    end

    client_config.freeze
  rescue StandardError => e
    rlog.error("[#{request_id}] PuavoRest::OAuth2::get_client_configuration_by_id(): #{e}")
    nil
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
