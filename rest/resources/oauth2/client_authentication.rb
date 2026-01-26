# frozen_string_literal: true

# OAuth2 client authentication

require 'jwt'
require 'openssl'

module PuavoRest
module OAuth2
module ClientAuthentication

ClientAuthenticationContext = Struct.new(
  :auth_type,           # :client_secret_basic, :client_secret_post, :private_key_jwt
  :client_id,
  :client_secret,       # valid only if doing password auth
  :client_jwt_key,      # valid only if doing public key auth
  :auth_data,           # contains the authentication record that was used to authenticate the client (can be nil)
  keyword_init: true
)

# Attempts to detect how the client is authenticating themselves. Analyzes the request headers
# and parameters, and extracts the authentication data. If no known authentication method can
# be detected, automatically halts the request with an appropriate error message and status.
def detect_authentication_context(request_id)
  have_http_authorization = request.env.include?('HTTP_AUTHORIZATION')
  have_client_id = params.include?('client_id')
  have_client_secret = params.include?('client_secret')
  have_client_assertion = params.include?('client_assertion_type') && params.include?('client_assertion')

  if have_http_authorization && !have_client_id && !have_client_secret && !have_client_assertion
    logger.info("[#{request_id}] Found HTTP_AUTHORIZATION header in the request, assuming client_secret_basic authentication")

    # Just a normal HTTP basic auth
    credentials = request.env.fetch('HTTP_AUTHORIZATION', '').split
    credentials = Base64.strict_decode64(credentials[1])
    credentials = credentials.split(':')

    if credentials.count != 2
      # Tested (manually)
      raise 'the HTTP_AUTHORIZATION header does not contain a valid client_id:password combo'
    end

    ctx = ClientAuthenticationContext.new(
      auth_type: :client_secret_basic,
      client_id: credentials[0],
      client_secret: credentials[1],
    )
  elsif !have_http_authorization && have_client_id && have_client_secret && !have_client_assertion
    logger.info("[#{request_id}] Found client_id and client_secret parameters, assuming client_secret_post authentication")

    # Almost like HTTP basic auth
    ctx = ClientAuthenticationContext.new(
      auth_type: :client_secret_post,
      client_id: params['client_id'],
      client_secret: params['client_secret'],
    )
  elsif !have_http_authorization && have_client_id && !have_client_secret && have_client_assertion &&
        params.fetch('client_assertion_type', nil) == 'urn:ietf:params:oauth:client-assertion-type:jwt-bearer'
    logger.info("[#{request_id}] Found client_assertion and client_assertion_type parameters, assuming private JWT authentication")

    ctx = ClientAuthenticationContext.new(
      auth_type: :private_key_jwt,

      # Get the client ID from the request parameters. The client ID is inside the JWT, but
      # we cannot validate the JWT without loading the public key from the database, and we
      # cannot do that without the client ID. So the only way to resolve this chicken-egg
      # problem is to include the client ID in the request parameters. None of the specs
      # I can find (RFC or otherwise) says anything about this. Some OAuth2 providers do
      # mention this and they say you must also put the client ID in the request parameters.
      # As of 2026-01-22, these two providers mention client_id directly in their examples:
      #  Okta: https://developer.okta.com/docs/api/openapi/okta-oauth/guides/client-auth/
      #  Signicat: https://developer.signicat.com/docs/eid-hub/oidc/advanced-security/client-authentication-with-private-key-jwt/
      client_id: params['client_id'],

      # This is the JWT that has been signed with the client's private key, and we must open
      # it with the public key in our database
      client_jwt_key: params['client_assertion']
    )
  else
    rlog.error("[#{request_id}] 'The client did not provide any way to authenticate themselves'")
    json_error('unauthorized_client', request_id: request_id)
  end

  # If we get here, we have a valid authentication context. Validate the client ID.
  unless OAuth2.valid_client_id?(ctx.client_id)
    # Tested
    rlog.error("[#{request_id}] Client ID #{ctx.client_id.inspect} is malformed")
    json_error('unauthorized_client', request_id: request_id)
  end

  ctx
rescue StandardError => e
  puts e
  rlog.error("[#{request_id}] #{e}")
  json_error('invalid_request', request_id: request_id)
end

# Load client configuration. Will halt the request if the client cannot be found,
# or it's not active.
def load_client_config(client_id, request_id)
  clients = ClientDatabase.new
  client_config = clients.get_token_client(client_id)
  clients.close

  if client_config.nil?
    # Tested
    rlog.error("[#{request_id}] Unknown/invalid client")
    json_error('unauthorized_client', request_id: request_id)
  end

  unless client_config['enabled']
    # Tested
    rlog.error("[#{request_id}] This client exists but it has been disabled")
    json_error('unauthorized_client', request_id: request_id)
  end

  client_config
end

# Authenticates the client. Halts the request if it cannot be done or there are
# errors. If your code continues running after this, the client was authenticated.
def authenticate_client(auth_ctx, client_config, request_id)
  # A client can have multiple authentication records, especially if a key rotation
  # has been scheduled. Inactive records have been removed during the database query,
  # now filter by authentication type.
  # TODO: Why not do this directly in the database query?
  client_authentication = client_config['client_authentication'].select do |a|
    a['auth_type'] == auth_ctx.auth_type.to_s
  end

  # Reject expired entries and entries that aren't valid yet
  now = Time.now.utc
  client_authentication.select! { |a| a['not_before'].nil? || now >= parse_postgres_timestamp(a['not_before']) }
  client_authentication.select! { |a| a['expires'].nil?    || now <  parse_postgres_timestamp(a['expires'])    }

  if client_authentication.empty?
    # Tested
    rlog.error("[#{request_id}] No active/valid authentication records found for this client")
    json_error('unauthorized_client', request_id: request_id)
  end

  # There must be only one active record available
  if client_authentication.count != 1
    # Tested
    keys = client_authentication.collect { |a| a['id'] }
    rlog.error("[#{request_id}] More than one (#{keys.join(', ')}) active authentication records for this client")
    json_error('unauthorized_client', request_id: request_id)
  end

  auth_ctx.auth_data = client_authentication[0]

  # Authenticate
  case auth_ctx.auth_type
    when :client_secret_basic, :client_secret_post
      # Tested
      do_password_auth(auth_ctx, request_id)

    when :private_key_jwt
      # Tested
      do_public_key_auth(auth_ctx, request_id)

    else
      # Tested (manually, by editing the database directly and breaking some checks elsewhere, so not
      # a very good test TBH)
      rlog.error("[#{request_id}] Unsupported requested_auth_type #{requested_auth_type.inspect}")
      json_error('unauthorized_client', request_id: request_id)
  end

  # If we get here, the client has been authenticated. No need to return anything, since
  # the method halts if something goes wrong or the client could not be authenticated.
  rlog.info("[#{request_id}] Client authorized using record #{auth_ctx.auth_data['id'].inspect} (#{auth_ctx.auth_type})")
rescue StandardError => e
  # Tested (manually)
  rlog.error("[#{request_id}] Unhandled exception in authenticate_client(): #{e}")
  json_error('unauthorized_client', request_id: request_id)
end

# Authenticates the client using a client ID and password
def do_password_auth(auth_ctx, request_id)
  hashed_password = auth_ctx.auth_data.fetch('password_hash', nil)

  if hashed_password.nil? || hashed_password.strip.empty?
    # Tested (manually, by intentionally changing the password to an empty string in psql)
    rlog.error("[#{request_id}] Empty hashed password specified in the database for a " \
               "token client, refusing access")
    json_error('unauthorized_client', request_id: request_id)
  end

  unless Argon2::Password.verify_password(auth_ctx.client_secret, hashed_password)
    # Tested
    rlog.error("[#{request_id}] Invalid client password")
    json_error('unauthorized_client', request_id: request_id)
  end
rescue StandardError => e
  rlog.error("[#{request_id}] Password authentication failed: #{e}")
  json_error('unauthorized_client', request_id: request_id)
end

# Authenticates the client using a client ID and a public key
def do_public_key_auth(auth_ctx, request_id)
  if auth_ctx.auth_data['public_key']
    validate_jwt_pem(auth_ctx, request_id)
  elsif auth_ctx.auth_data['jwks']
    validate_jwt_jwks(auth_ctx, request_id)
  else
    # Tested (manually)
    rlog.error("[#{request_id}] Both public_key and jwks fields in the auth_ctx struct (record #{auth_ctx.auth_data['id']}) are nil")
    json_error('unauthorized_client', request_id: request_id)
  end
rescue StandardError => e
  # Tested
  rlog.error("[#{request_id}] JWT validation failed: #{e}")
  json_error('unauthorized_client', request_id: request_id)
end

# Validates the JWT using a public key in PEM format
def validate_jwt_pem(auth_ctx, request_id)
  public_key = OpenSSL::PKey.read(auth_ctx.auth_data['public_key'])

  # Load the JWT from the request parameters. We need to decode it first without verifying
  # the signature, because we don't know yet which public key will validate it. But we can
  # perform minor validation on it on certain fields.
  jwt = JWT.decode(auth_ctx.client_jwt_key, public_key, true, {
    algorithm: 'ES256',
    verify_iat: true,
    iss: auth_ctx.client_id,
    verify_iss: true,
    aud: ISSUER,        # it's for us so we're the audience
    verify_aud: true
  })

  # The public key works and the JWT is valid. If key ID and/or algorithm have been specified,
  # verify them too.
  auth_id = auth_ctx.auth_data['id']

  if auth_ctx.auth_data['pk_kid']
    # Tested
    unless jwt[1].fetch('kid', nil) == auth_ctx.auth_data['pk_kid']
      rlog.error("[#{request_id}] Authentication record #{auth_id.inspect} validates the JWT, but the "\
                 "key ID does not match (got #{jwt[1].fetch('kid', nil).inspect}, expected #{auth_ctx.auth_data['pk_kid'].inspect})")
      json_error('unauthorized_client', request_id: request_id)
    end
  end

  if auth_ctx.auth_data['pk_alg']
    # Tested, but only partially. The JWT gem verifies the algorithm, so we can neither omit it nor set it to invalid values.
    unless jwt[1].fetch('alg', nil) == auth_ctx.auth_data['pk_alg']
      rlog.error("[#{request_id}] Authentication record #{auth_id.inspect} validates the JWT, but the "\
                 "algorithm does not match (got #{jwt[1].fetch('alg', nil).inspect}, expected #{auth_ctx.auth_data['pk_alg'].inspect})")
      json_error('unauthorized_client', request_id: request_id)
    end
  end

  # They public key is valid. No need to return anything.
end

# Validates the JWT using a public key in a JWK keyset
def validate_jwt_jwks(auth_ctx, request_id)
  # Load the JWKS into a keyfinder
  jwks_json = JSON.parse(auth_ctx.auth_data['jwks'])
  key_finder = JWT::JWK::KeyFinder.new(jwks: JWT::JWK::Set.new(jwks_json))

  et = JWT::EncodedToken.new(auth_ctx.client_jwt_key)

  # Support both ES256 and RS256 algorithms
  # TODO: I'm not sure if this actually works. I don't have any RSA keys to test with, but it shouldn't be
  # a problem, because currently no client uses RSA keys. This probably won't work as expected. I will test
  # this properly later.
  begin
    et.verify!(signature: { algorithm: 'ES256', key_finder: key_finder })
  rescue StandardError => e
    et.verify!(signature: { algorithm: 'RS256', key_finder: key_finder })
  end

  # Validate the claims
  et.verify_claims!(:iat, :exp, :nbf)

  et.verify_claims!({
    iss: auth_ctx.client_id,
    aud: ISSUER,        # it's for us so we're the audience
  })

  # RFC 9068 section 4 says this MUST be checked. The jwt gem does not put it there
  # and it does not validate it, so do it manually.
  raise "invalid header 'typ' value #{typ.inspect}; expected \"at+jwt\"" unless et.header['typ'] == 'at+jwt'

  # They public key is valid. No need to return anything.
end

def parse_postgres_timestamp(s)
  Time.strptime("#{s} UTC", '%Y-%m-%d %H:%M:%S %Z')
end

end
end   # module OAuth2
end   # module PuavoRest
