# frozen_string_literal: true

# Various helper methods used in OAuth2 / OpenID Connect test files

# Activates the specified external services in all organisations in puavo-standalone
def activate_organisation_services(s)
  PuavoRest::Organisation.all.each do |org|
    unless ['puavo.net', 'hogwarts.puavo.net', ''].include?(org.domain)
      org.external_services = s
      org.save!
    end
  end

  PuavoRest::Organisation.refresh
end

# Connects to the OAuth 2 client SQL database
def oauth2_client_db
  db_config = CONFIG['oauth2']['client_database']

  PG.connect(hostaddr: db_config['host'],
             port: db_config['port'],
             dbname: db_config['database'],
             user: db_config['user'],
             password: db_config['password'])
end

# Creates one or more login clients
def setup_login_clients(clients, remove_old: true)
  db = oauth2_client_db()

  if remove_old
    db.exec("DELETE FROM login_clients WHERE client_id like 'test_login_%';")
  end

  array_encoder = PG::TextEncoder::Array.new
  now = Time.now.utc

  clients.each do |client|
    db.exec_params(
      'INSERT INTO login_clients(client_id, enabled, puavo_service_dn, ldap_id, ' \
      'allowed_redirects, allowed_scopes, created, modified) VALUES ' \
      "($1, $2, $3, $4, $5, $6, $7, $8)",
      [client[:client_id], client.fetch(:enabled, false), client[:puavo_service_dn],
      client.fetch(:ldap_id, nil), array_encoder.encode(client[:redirects]),
      array_encoder.encode(client[:scopes]), now, now]
    )
  end

  db.close
end

# Decodes a JWT token using the specified public key (in PEM format)
def decode_token(token, key: OAUTH2_TOKEN_VERIFICATION_PUBLIC_KEY, audience: 'puavo-rest-v4')
  decoded_token = JWT.decode(token, key, true, {
    algorithm: 'ES256',

    verify_iat: true,

    iss: 'https://api.opinsys.fi',
    verify_iss: true,

    aud: audience,
    verify_aud: true,
  })

  assert_equal decoded_token[1]['typ'], 'at+jwt'
  decoded_token[0]
end

def format_uri(url, client_id: nil, redirect_uri: nil, response_type: nil, scope: nil, extra: nil)
  uri = URI(url)

  params = {}

  params['client_id'] = client_id unless client_id.nil?
  params['redirect_uri'] = redirect_uri unless client_id.nil?
  params['response_type'] = response_type unless response_type.nil?
  params['scope'] = scope unless scope.nil?

  # Extra parameters if needed
  params.merge!(extra) if extra.instance_of?(Hash)

  uri.query = URI.encode_www_form(params)
  uri.to_s
end

# Goes to the OpenID Connect login form
def go_to_login_form(client_id:, redirect_uri:, scope:, service_title: nil, extra: nil)
  get format_uri('/oidc/authorize', client_id: client_id, redirect_uri: redirect_uri, response_type: 'code', scope: scope, extra: extra)

  # Always do basic validation
  assert_equal last_response.status, 401
  assert get_named_form_value('type') == 'oidc'
  assert last_response.body.include?(service_title) if service_title

  # Return these parameters to the caller, as they're needed if you want to post the form
  {
    request_id: get_named_form_value('request_id'),
    state_key: get_named_form_value('state_key'),
    return_to: get_named_form_value('return_to'),
  }
end

# Posts the OpenID Connect login form with the specified parameters
def do_login(username:, password:, params:)
  post '/oidc/authorize/post', {
    type: 'oidc',
    request_id: params[:request_id],
    state_key: params[:state_key],
    return_to: params[:return_to],
    username: username,
    password: password
  }
end

# Retrieves the value of the named input element
def get_named_form_value(name)
  css("input[name=\"#{name}\"]").first.attributes['value'].value
end
