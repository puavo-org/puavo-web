# frozen_string_literal: true

# Client credentials grant request, for machine <-> machine communication with OAuth tokens

require 'jwt'

module PuavoRest
module OAuth2
module ClientCredentialsGrant
def client_credentials_grant(request_id)
  rlog.info("[#{request_id}] This is a client credentials grant request")

  # ----------------------------------------------------------------------------------------------
  # Verify the content type (RFC 6749 section 2.3.1.)

  content_type = request.env.fetch('CONTENT_TYPE', nil)

  unless content_type == 'application/x-www-form-urlencoded'
    # Tested (manually, cannot be automated as the URL library used in the tests does not
    # permit fiddling with the header)
    rlog.error("[#{request_id}] Received a client_credentials request with an incorrect " \
               "Content-Type header (#{content_type.inspect})")
    json_error('invalid_request', request_id: request_id)
  end

  # ----------------------------------------------------------------------------------------------
  # Authenticate the client

  # These calls automatically halt the request if there are errors
  auth_ctx = detect_authentication_context(request_id)
  client_config = load_client_config(auth_ctx.client_id, request_id)
  authenticate_client(auth_ctx, client_config, request_id)

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

  if client_config.include?('required_service_dn') &&
      !client_config['required_service_dn'].nil? &&
      !client_config['required_service_dn'].empty?
    custom_claims['required_service_dn'] = client_config['required_service_dn']
    rlog.info("[#{request_id}] Token usage is restricted to organisations where the external service " \
              "#{client_config['required_service_dn'].inspect} is active")
  end

  # ----------------------------------------------------------------------------------------------
  # Generate the token. Put it in a JWT and sign the JWT with a private key,
  # so we now have a self-validating token.

  expires_in = client_config['expires_in'].to_i

  token = build_access_token(
    request_id,
    ldap_id: client_config['ldap_id'],
    client_id: auth_ctx.client_id,
    subject: auth_ctx.client_id,
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
                            client_id: auth_ctx.client_id,
                            raw_requested_scopes: params.fetch('scope', ''),
                            raw_token: token[:raw_token],
                            request: request)

  headers['Cache-Control'] = 'no-store'
  headers['Pragma'] = 'no-cache'

  json(out)
rescue StandardError => e
  rlog.error("[#{request_id}] Unhandled exception in client_credentials_grant(): #{e}")
  json_error('server_error', request_id: request_id)
end

end   # module ClientCredentialsGrant
end   # module OAuth2
end   # module PuavoRest
