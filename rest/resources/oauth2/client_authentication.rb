# frozen_string_literal: true

# OAuth2 client authentication

module PuavoRest
module OAuth2
module ClientAuthentication

ClientAuthenticationContext = Struct.new(
  :auth_type,           # :client_secret_basic, :client_secret_post
  :client_id,
  :client_secret,       # valid only if doing password auth
  :auth_data,           # contains the authentication record that was used to authenticate the client (can be nil)
  keyword_init: true
)

# Attempts to detect how the client is authenticating themselves. Analyzes the request headers
# and parameters, and extracts the authentication data. If no known authentication method can
# be detected, automatically halts the request with an appropriate error message and status.
def detect_authentication_context(request_id)
  have_http_authorization = request.env.include?('HTTP_AUTHORIZATION')
  have_client_id = params.include?('client_id')

  if have_http_authorization && !have_client_id
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
  elsif !have_http_authorization && have_client_id && have_client_secret
    logger.info("[#{request_id}] Found client_id and client_secret parameters, assuming client_secret_post authentication")

    # Almost like HTTP basic auth
    ctx = ClientAuthenticationContext.new(
      auth_type: :client_secret_post,
      client_id: params['client_id'],
      client_secret: params['client_secret'],
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
      do_password_auth(auth_ctx, request_id)

    else
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

end
end   # module OAuth2
end   # module PuavoRest
