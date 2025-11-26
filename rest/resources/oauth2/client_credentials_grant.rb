# frozen_string_literal: true

# Client credentials grant request, for machine <-> machine communication with OAuth tokens

module PuavoRest
module OAuth2
module ClientCredentialsGrant
def client_credentials_grant(request_id)
  rlog.info("[#{request_id}] This is a client credentials grant request")

  # RFC 6749 section 2.2.
  content_type = request.env.fetch('CONTENT_TYPE', nil)

  unless content_type == 'application/x-www-form-urlencoded'
    # Tested (manually, cannot be automated as the URL library used in the tests does not
    # permit fiddling with the header)
    rlog.error("[#{request_id}] Received a client_credentials request with an incorrect " \
               "Content-Type header (#{content_type.inspect})")
    json_error('invalid_request', request_id: request_id)
  end

  # ----------------------------------------------------------------------------------------------
  # Load client credentials from the request

  # TODO: We need to support other client authorization systems

  unless request.env.include?('HTTP_AUTHORIZATION')
    # Tested
    rlog.error("[#{request_id}] Received a client_credentials request without an HTTP_AUTHORIZATION header")
    json_error('invalid_request', request_id: request_id)
  end

  begin
    credentials = request.env.fetch('HTTP_AUTHORIZATION', '').split
    credentials = Base64.strict_decode64(credentials[1])
    credentials = credentials.split(':')

    if credentials.count != 2
      # Tested (manually)
      rlog.error("[#{request_id}] the HTTP_AUTHORIZATION header does not contain a valid client_id:password combo")
      json_error('invalid_request', request_id: request_id)
    end
  rescue StandardError => e
    # Tested (manually)
    rlog.error("[#{request_id}] Could not parse the HTTP_AUTHORIZATION header: #{e}")
    rlog.error("[#{request_id}] Raw header: #{request.env['HTTP_AUTHORIZATION'].inspect}")
    json_error('invalid_request', request_id: request_id)
  end

  # ----------------------------------------------------------------------------------------------
  # Authenticate the client

  rlog.info("[#{request_id}] Client ID: #{credentials[0].inspect}")

  unless OAuth2.valid_client_id?(credentials[0])
    # Tested
    rlog.error("[#{request_id}] Malformed client ID")
    json_error('unauthorized_client', request_id: request_id)
  end

  clients = ClientDatabase.new
  client_config = clients.get_token_client(credentials[0])
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

  hashed_password = client_config.fetch('client_password', nil)

  if hashed_password.nil? || hashed_password.strip.empty?
    # Tested (manually, by intentionally changing the password to an empty string in psql)
    rlog.error("[#{request_id}] Empty hashed password specified in the database for a " \
               "token client, refusing access")
    json_error('unauthorized_client', request_id: request_id)
  end

  unless Argon2::Password.verify_password(credentials[1], hashed_password)
    # Tested
    rlog.error("[#{request_id}] Invalid client password")
    json_error('unauthorized_client', request_id: request_id)
  end

  rlog.info("[#{request_id}] Client authorized")

  # ----------------------------------------------------------------------------------------------
  # Validate the scopes. RFC 6479 says these are optional for client credential requests,
  # but we require them. RFC 6479 section 3.3. says that if the scopes cannot be used,
  # we must either use default scopes or fail the request. We have no default scopes,
  # so we can only fail the request.

  # TODO: Is the "openid" scope required here?
  scopes = Scopes.clean_scopes(request_id, params.fetch('scope', ''), Scopes::BUILTIN_PUAVO_OAUTH2_SCOPES,
                               client_config, require_openid: false)

  unless scopes.success
    # Can happen only if the "openid" scope is needed but wasn't supplied (see the TODO above)
    # TODO: Test this
    json_error('invalid_scope', request_id: request_id)
  end

  if scopes.scopes.empty?
    # Tested
    rlog.error("[#{request_id}] The cleaned-up scopes list is completely empty")
    json_error('invalid_scope', request_id: request_id)
  end

  # ----------------------------------------------------------------------------------------------
  # Firewalling

  custom_claims = {}

  # Organisation restriction
  if client_config.include?('allowed_organisations') &&
      !client_config['allowed_organisations'].nil? &&
      !client_config['allowed_organisations'].empty?
    custom_claims['allowed_organisations'] = Array(client_config['allowed_organisations'])
    rlog.info("[#{request_id}] Token is only allowed in these organisations: " \
              "#{custom_claims['allowed_organisations'].inspect}")
  end

  # Endpoint restriction
  if client_config.include?('allowed_endpoints') &&
      !client_config['allowed_endpoints'].nil? &&
      !client_config['allowed_endpoints'].empty?
    custom_claims['allowed_endpoints'] = Array(client_config['allowed_endpoints'])
    rlog.info("[#{request_id}] Token is only allowed in these endpoints: " \
              "#{custom_claims['allowed_endpoints'].inspect}")
  end

  # ----------------------------------------------------------------------------------------------
  # Generate the token. Put it in a JWT and sign the JWT with a private key,
  # so we now have a self-validating token.

  expires_in = client_config['expires_in'].to_i

  token = build_access_token(
    request_id,
    ldap_id: client_config['ldap_id'],
    client_id: credentials[0],
    subject: credentials[0],
    scopes: scopes[:scopes],
    expires_in: expires_in,
    custom_claims: custom_claims
  )

  unless token[:success]
    # TODO: Need to test this
    json_error('invalid_request', request_id: request_id)
  end

  out = {
    'access_token' => token[:access_token],
    'token_type' => 'Bearer',
    'expires_in' => expires_in,
    'puavo_request_id' => request_id
  }

  rlog.info("[#{request_id}] Issued access token #{token[:raw_token]['jti'].inspect}, " \
            "expires at #{Time.at(token[:expires_at])}")

  audit_issued_access_token(request_id,
                            ldap_id: client_config['ldap_id'],
                            client_id: credentials[0],
                            raw_requested_scopes: params.fetch('scope', ''),
                            raw_token: token[:raw_token],
                            request: request)

  headers['Cache-Control'] = 'no-store'
  headers['Pragma'] = 'no-cache'

  json(out)
end
end   # module ClientCredentialsGrant
end   # module OAuth2
end   # module PuavoRest
