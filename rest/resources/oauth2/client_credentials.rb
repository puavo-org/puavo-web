# RFC 6749 section 4.4. Client Credentials Grant
# This generates access tokens for non-interactive machine <-> machine communication

require 'base64'
require 'yaml'
require 'argon2'

require_relative './scopes'
require_relative './access_token'
require_relative './helpers'

module PuavoRest
module OAuth2
  def client_credentials_grant(request_id)
    rlog.info("[#{request_id}] This is a client credentials grant request")

    # RFC 6749 section 2.2.
    content_type = request.env.fetch('CONTENT_TYPE', nil)

    unless content_type == 'application/x-www-form-urlencoded'
      rlog.error("[#{request_id}] Received a client_credentials request with an incorrect Content-Type header (#{content_type.inspect})")
      return json_error('invalid_request', request_id: request_id)
    end

    # ----------------------------------------------------------------------------------------------
    # Load client credentials from the request

    # TODO: We need to support other client authorization systems

    unless request.env.include?('HTTP_AUTHORIZATION')
      rlog.error("[#{request_id}] Received a client_credentials request without an HTTP_AUTHORIZATION header")
      return json_error('invalid_request', request_id: request_id)
    end

    begin
      credentials = request.env.fetch('HTTP_AUTHORIZATION', '').split(' ')
      credentials = Base64::strict_decode64(credentials[1])
      credentials = credentials.split(':')

      if credentials.count != 2
        rlog.error("[#{request_id}] the HTTP_AUTHORIZATION header does not contain a valid client_id:password combo")
        return json_error('invalid_request', request_id: request_id)
      end
    rescue StandardError => e
      rlog.error("[#{request_id}] Could not parse the HTTP_AUTHORIZATION header: #{e}")
      rlog.error("[#{request_id}] Raw header: #{request.env['HTTP_AUTHORIZATION'].inspect}")
      return json_error('invalid_request', request_id: request_id)
    end

    # ----------------------------------------------------------------------------------------------
    # Authenticate the client

    rlog.info("[#{request_id}] Client ID: #{credentials[0].inspect}")

    client_config = get_client_configuration_by_id(request_id, credentials[0], :token)

    if client_config.nil?
      rlog.error("[#{request_id}] Unknown/invalid client")
      return json_error('unauthorized_client', request_id: request_id)
    end

    unless client_config['enabled'] == 't'
      rlog.error("[#{request_id}] This client exists but it has been disabled")
      return json_error('unauthorized_client', request_id: request_id)
    end

    hashed_password = client_config.fetch('client_password', nil)

    if hashed_password.nil? || hashed_password.strip.empty?
      rlog.error("[#{request_id}] Empty hashed password specified in the database for a token client, refusing access")
      return json_error('unauthorized_client', request_id: request_id)
    end

    unless Argon2::Password.verify_password(credentials[1], hashed_password)
      rlog.error("[#{request_id}] Invalid client password")
      return json_error('unauthorized_client', request_id: request_id)
    end

    rlog.info("[#{request_id}] Client authorized")

    # ----------------------------------------------------------------------------------------------
    # Validate the scopes. RFC 6479 says these are optional for client credential requests,
    # but we require them. RFC 6479 section 3.3. says that if the scopes cannot be used,
    # we must either use default scopes or fail the request. We have no default scopes,
    # so we can only fail the request.

    # TODO: Is the "openid" scope required here?
    scopes = clean_scopes(request_id,
                          params.fetch('scope', ''),
                          BUILTIN_PUAVO_OAUTH2_SCOPES,
                          client_config,
                          require_openid: false)

    unless scopes[:success]
      return json_error('invalid_scope', request_id: request_id)
    end

    if scopes[:scopes].empty?
      rlog.error("[#{request_id}] The cleaned-up scopes list is completely empty")
      return json_error('invalid_scope', request_id: request_id)
    end

    # ----------------------------------------------------------------------------------------------
    # Firewalling

    custom_claims = {}

    # Organisation restriction
    if client_config.include?('allowed_organisations') &&
        !client_config['allowed_organisations'].nil? &&
        !client_config['allowed_organisations'].empty?
      custom_claims['allowed_organisations'] = Array(client_config['allowed_organisations'])
      rlog.info("[#{request_id}] Token is only allowed in these organisations: #{custom_claims['allowed_organisations'].inspect}")
    end

    # Endpoint restriction
    if client_config.include?('allowed_endpoints') &&
        !client_config['allowed_endpoints'].nil? &&
        !client_config['allowed_endpoints'].empty?
      custom_claims['allowed_endpoints'] = Array(client_config['allowed_endpoints'])
      rlog.info("[#{request_id}] Token is only allowed in these endpoints: #{custom_claims['allowed_endpoints'].inspect}")
    end

    # ----------------------------------------------------------------------------------------------
    # Generate the token. Put it in a JWT and sign the JWT with a private key,
    # so we now have a self-validating token.

    # TODO: Should this be client-configurable?
    expires_in = 3600

    token = build_access_token(request_id,
                               subject: credentials[0],
                               client_id: credentials[0],
                               scopes: scopes[:scopes],
                               expires_in: expires_in,
                               custom_claims: custom_claims)

    unless token[:success]
      return json_error('invalid_request', request_id: request_id)
    end

    out = {
      'access_token' => token[:access_token],
      'token_type' => 'Bearer',
      'expires_in' => expires_in,
      'puavo_request_id' => request_id,
    }

    rlog.info("[#{request_id}] Issued access token #{token[:jti].inspect}, expires at #{Time.at(token[:expires_at])}")

    headers['Cache-Control'] = 'no-store'
    headers['Pragma'] = 'no-cache'

    json(out)
  end
end   # module OAuth2
end   # module PuavoRest
