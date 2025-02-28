# frozen_string_literal: true

# OAuth2 token auditing

require 'pg'
require_relative 'helpers'

module PuavoRest
module OAuth2
  # TODO: This method has to be marked "self" because it's called from auth.rb which
  # has no proper access to this module. Similarly, this method cannot call the helper
  # functions at the bottom. This probably can be solved in some clean and nice way.
  def self.audit_token_use(status:, error: nil, token_id: nil, organisation: nil, client_id: nil,
                           ldap_user_dn: nil, audience: nil, requested_scopes: nil,
                           target_endpoint: nil, raw_token: nil, request: nil)

    return unless CONFIG['oauth2'].fetch('audit', {}).fetch('enabled', false)

    db_config = CONFIG['oauth2']['client_database']

    db = PG.connect(hostaddr: db_config['host'],
                    port: db_config['port'],
                    dbname: db_config['database'],
                    user: db_config['user'],
                    password: db_config['password'])

    encoder = PG::TextEncoder::Array.new

    db.exec_params(
      'INSERT INTO token_usage_history(id, token_id, timestamp, request_ip, status, error, ' \
      'organisation, client_id, ldap_user_dn, audience, requested_scopes, target_endpoint, raw_token) ' \
      'VALUES($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13)',
      [
        SecureRandom.uuid,
        token_id,
        Time.now.utc,
        CONFIG['oauth2'].fetch('audit', {}).fetch('ip_logging', false) ? request.ip : nil,
        status,
        error,
        organisation,
        client_id,
        ldap_user_dn,
        audience,
        encoder.encode(requested_scopes),
        target_endpoint,
        raw_token
      ]
    )

    db.close
  end

  def audit_issued_id_token(request_id, db, client_id:, ldap_user_dn:, raw_requested_scopes:,
                            issued_scopes:, redirect_uri:, raw_token:, request:)
    return unless auditing_enabled?

    encoder = PG::TextEncoder::Array.new

    db.exec_params(
      'INSERT INTO issued_tokens_history(id, issuer, request_ip, type, client_id, ldap_user_dn, ' \
      'subject, audience, issued_at, expires_at, matching_redirect_uri, raw_requested_scopes, ' \
      'issued_scopes) VALUES($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13)',
      [
        raw_token['jti'],
        raw_token['iss'],
        ip_logging? ? request.ip : nil,
        'id',
        client_id,
        ldap_user_dn,
        raw_token['sub'],
        raw_token['aud'],
        Time.at(raw_token['iat']).utc,
        Time.at(raw_token['exp']).utc,
        redirect_uri,
        raw_requested_scopes,
        encoder.encode(issued_scopes),
      ]
    )
  end

  def audit_issued_access_token(request_id, db, client_id:, ldap_user_dn:, raw_requested_scopes:,
                                raw_token:, request:)
    return unless auditing_enabled?

    encoder = PG::TextEncoder::Array.new

    db.exec_params(
      'INSERT INTO issued_tokens_history(id, issuer, request_ip, type, client_id, ldap_user_dn, ' \
      'subject, audience, issued_at, expires_at, raw_requested_scopes, issued_scopes, ' \
      'issued_endpoints, issued_organisations)' \
      'VALUES($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14)',
      [
        raw_token['jti'],
        raw_token['iss'],
        ip_logging? ? request.ip : nil,
        'access',
        client_id,
        ldap_user_dn,
        raw_token['sub'],
        raw_token['aud'],
        Time.at(raw_token['iat']).utc,
        Time.at(raw_token['exp']).utc,
        raw_requested_scopes,
        encoder.encode(raw_token['scopes'].split),
        raw_token.include?('allowed_endpoints') ? encoder.encode(raw_token['allowed_endpoints']) : nil,
        raw_token.include?('allowed_organisations') ? encoder.encode(raw_token['allowed_organisations']) : nil,
      ]
    )
  end

  def auditing_enabled?
    CONFIG['oauth2'].fetch('audit', {}).fetch('enabled', false)
  end

  def ip_logging?
    CONFIG['oauth2'].fetch('audit', {}).fetch('ip_logging', false)
  end
end   # module OAuth2
end   # module PuavoRest
