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
def oauth2_client_db(&block)
  db_config = CONFIG['oauth2']['client_database']

  db = PG.connect(hostaddr: db_config['host'],
                  port: db_config['port'],
                  dbname: db_config['database'],
                  user: db_config['user'],
                  password: db_config['password'])

  block.call(db)
  db.close()
end

def create_login_client(db, client_id, puavo_service_dn, allowed_redirects, allowed_scopes, enabled: true)
  array_encoder = PG::TextEncoder::Array.new
  now = Time.now.utc

  db.exec_params(
    'INSERT INTO login_clients(client_id, enabled, puavo_service_dn, allowed_redirects, allowed_scopes, ' \
    'created, modified) VALUES ($1, $2, $3, $4, $5, $6, $7)',
    [client_id, enabled, puavo_service_dn, array_encoder.encode(allowed_redirects),
    array_encoder.encode(allowed_scopes), now, now]
  )
end

# Creates one or more login clients
def setup_login_clients(clients, remove_old: true)
  oauth2_client_db do |db|
    db.exec("DELETE FROM login_clients WHERE client_id like 'test_login_%';") if remove_old

    clients.each do |client|
      create_login_client(db, client[:client_id], client[:puavo_service_dn], client[:redirects], client[:scopes], enabled: client.fetch(:enabled, false))
    end
  end
end

# Deletes all test client data used in these tests
def delete_test_client_data(db)
  db.exec("DELETE FROM login_clients WHERE client_id like 'test_login_%';")
  db.exec("DELETE FROM token_clients WHERE client_id like 'test_client_%';")
  db.exec("DELETE FROM client_authentication WHERE client_id like 'test_client_%';")
end

# Creates a new token client
def create_token_client(db, client_id, scopes, endpoints: [], ldap_id: 'admin', enabled: true, service_dn: nil)
  array_encoder = PG::TextEncoder::Array.new
  now = Time.now.utc

  db.exec_params(
    'INSERT INTO token_clients(client_id, enabled, ldap_id, allowed_scopes, ' \
    'allowed_endpoints, required_service_dn, created, modified) VALUES ' \
    '($1, $2, $3, $4, $5, $6, $7, $8)',
    [client_id, enabled, ldap_id, array_encoder.encode(scopes), array_encoder.encode(endpoints), service_dn, now, now]
  )
end

def delete_token_client(db, client_id, auth: false)
  db.exec_params('DELETE FROM token_clients WHERE client_id = $1;', [client_id])
  db.exec_params('DELETE FROM client_authentication WHERE client_id = $1;', [client_id]) if auth
end

def create_client_authentication(db, client_id, auth_type, params: {}, enabled: true, not_before: nil, expires: nil)
  now = Time.now.utc

  case auth_type
    when 'client_secret_basic', 'client_secret_post'
      if params[:password]
        password_hash = Argon2::Password.new(profile: :rfc_9106_low_memory).create(params[:password])
      elsif params[:password_hash]
        password_hash = params[:password_hash]
      else
        raise 'create_client_authentication(): missing both password and password_hash'
      end

      db.exec_params(
        'INSERT INTO client_authentication(id, client_id, enabled, auth_type, password_hash, not_before, expires, created, modified) VALUES ' \
        '($1, $2, $3, $4, $5, $6, $7, $8, $9)',
        [SecureRandom.uuid, client_id, enabled, auth_type.to_s, password_hash, not_before, expires, now, now]
      )

    when 'private_key_jwt'
      if params[:public_key]
        db.exec_params(
          'INSERT INTO client_authentication(id, client_id, enabled, auth_type, public_key, pk_kid, pk_alg, not_before, expires, created, modified) VALUES ' \
          '($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11)',
          [SecureRandom.uuid, client_id, enabled, 'private_key_jwt', params[:public_key], params.fetch(:pk_kid, nil),
          params.fetch(:pk_alg, nil), not_before, expires, now, now]
        )

      elsif params[:jwks]
        db.exec_params(
          'INSERT INTO client_authentication(id, client_id, enabled, auth_type, jwks, not_before, expires, created, modified) VALUES ' \
          '($1, $2, $3, $4, $5, $6, $7, $8, $9)',
          [SecureRandom.uuid, client_id, enabled, 'private_key_jwt', params[:jwks].to_json, not_before, expires, now, now]
        )

      else
        raise 'create_client_authentication(): missing both public_key and jwks for private_key_jwt auth'
      end

    else
      raise "create_client_authentication(): unknown auth_type #{auth_type.inspect}"
  end
end

def read_pem(filename)
  OpenSSL::PKey.read(File.read(filename))
end

def load_default_public_key
  read_pem(CONFIG['oauth2']['key_files']['public_pem'])
end

def load_default_private_key
  read_pem(CONFIG['oauth2']['key_files']['private_pem'])
end

# Decodes a JWT token using a public key in PEM format. The key is the default built-in public key, by default.
def decode_token(token, key: :default, audience: 'puavo-rest-v4')
  if key == :default
    # Load the default development public key
    key = load_default_public_key()
  end

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

# Decodes a token with a key stored in a JWKS. The JWKS object is assumed to be Ruby Hash, not a string of JSON.
# Supports only ES256 keys!
def decode_token_jwks(token, jwks, audience: 'puavo-rest-v4')
  key_finder = JWT::JWK::KeyFinder.new(jwks: JWT::JWK::Set.new(jwks))

  et = JWT::EncodedToken.new(token)
  et.verify!(signature: { algorithm: 'ES256', key_finder: key_finder })

  # Validate the claims
  et.verify_claims!(:iat, :exp, :nbf)
  et.verify_claims!({ iss: 'https://api.opinsys.fi', aud: audience })

  # RFC 9068 section 4 says this MUST be checked. The jwt gem does not put it there
  # and it does not validate it, so do it manually.
  raise "invalid header 'typ' value #{typ.inspect}; expected \"at+jwt\"" unless et.header['typ'] == 'at+jwt'

  et.payload
end

# Signs a token with arbitrary private key (in PEM format)
def sign_token_with_pem(key, subject:, scopes:, kid:)
  now = Time.now.utc.to_i

  claims = {
    'jti' => SecureRandom.uuid,
    'iat' => now,
    'nbf' => now,
    'exp' => now + 60,    # very short-lived tokens, just for testing
    'iss' => 'https://api.opinsys.fi',
    'sub' => subject,
    'aud' => 'puavo-rest-v4',
    'scopes' => scopes.join(' ')
  }

  JWT.encode(claims, key, 'ES256', { typ: 'at+jwt', kid: kid })
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
