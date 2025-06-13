# frozen_string_literal: true

# OAuth2 token auditing. Disabled by default.

require 'digest'

module PuavoRest
module Audit
  def audit_token_use(status:,
                      error: nil,
                      token_id: nil,
                      organisation: nil,
                      client_id: nil,
                      ldap_user_dn: nil,
                      audience: nil,
                      requested_scopes: nil,
                      requested_endpoint: nil,
                      raw_token: nil,
                      request: nil)

    return unless auditing_enabled?

    data = {
      id: SecureRandom.uuid,
      token_id: token_id,
      timestamp: Time.now.utc,
      ip: log_ip(request),
      status: status,
      error: error,
      organisation: organisation,
      client_id: client_id,
      ldap_user_dn: ldap_user_dn,
      aud: audience,
      requested_scopes: requested_scopes,
      requested_endpoint: requested_endpoint,
      raw_token: raw_token
    }

    rlog.info("OAUTH2 AUDIT TOKEN USE: #{data.to_json}")
  end

  def audit_issued_id_token(request_id,
                            client_id:,
                            ldap_user_dn:,
                            raw_requested_scopes:,
                            issued_scopes:,
                            redirect_uri:,
                            raw_token:,
                            request:)

    return unless auditing_enabled?

    data = {
      jti: raw_token['jti'],
      iss: raw_token['iss'],
      ip: log_ip(request),
      client_id: client_id,
      ldap_user_dn: ldap_user_dn,
      sub: raw_token['sub'],
      aud: raw_token['aud'],
      iat: Time.at(raw_token['iat']).utc,
      exp: Time.at(raw_token['exp']).utc,
      redirct_uri: redirect_uri,
      raw_requested_scopes: raw_requested_scopes,
      issued_scopes: issued_scopes
    }

    rlog.info("[#{request_id}] OAUTH2 AUDIT ID TOKEN: #{data.to_json}")
  end

  def audit_issued_access_token(request_id,
                                client_id:,
                                ldap_user_dn:,
                                raw_requested_scopes:,
                                raw_token:,
                                request:)

    return unless auditing_enabled?

    data = {
      jti: raw_token['jti'],
      iss: raw_token['iss'],
      ip: log_ip(request),
      client_id: client_id,
      ldap_user_dn: ldap_user_dn,
      sub: raw_token['sub'],
      aud: raw_token['aud'],
      iat: Time.at(raw_token['iat']).utc,
      exp: Time.at(raw_token['exp']).utc,
      raw_requested_scopes: raw_requested_scopes,
      scopes: raw_token['scopes'],
      allowed_endpoints: raw_token.fetch('allowed_endpoints', nil),
      allowed_organisations: raw_token.fetch('allowed_organisations', nil)
    }

    rlog.info("[#{request_id}] OAUTH2 AUDIT ACCESS TOKEN: #{data.to_json}")
  end

  def auditing_enabled?
    CONFIG['oauth2'].fetch('audit', {}).fetch('enabled', false)
  end

  def log_ip(request)
    return '(logging disabled)' unless CONFIG['oauth2'].fetch('audit', {}).fetch('ip_logging', false)
    Digest::SHA256.hexdigest(request.ip)
  end
end
end
