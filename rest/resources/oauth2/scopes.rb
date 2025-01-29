# frozen_string_literal: true

# OAuth2 scopes

require 'set'

module PuavoRest
module OAuth2
  # Allowed built-in scopes for OpenID Connect logins (not used with client credentials).
  # These scopes are also valid for the OIDC userinfo endpoint, but nowhere else ATM.
  BUILTIN_LOGIN_SCOPES = %w[
    openid
    profile
    email
    phone
    puavo.read.userinfo.organisation
    puavo.read.userinfo.schools
    puavo.read.userinfo.groups
    puavo.read.userinfo.ldap
    puavo.read.userinfo.admin
    puavo.read.userinfo.security
  ].to_set.freeze

  # Allowed built-in OAuth 2 access token scopes, for client credential requests.
  # At the moment, we have scopes only for the puavo-rest V4 API. Possible scopes
  # for other systems remain TBD.
  BUILTIN_PUAVO_OAUTH2_SCOPES = %w[
    puavo.read.organisation
    puavo.read.schools
    puavo.read.groups
    puavo.read.users
    puavo.read.devices
  ].to_set.freeze

  # Parses a string containing scopes separated by spaces, and removes the scopes that
  # aren't allowed for this client and also the invalid scopes.
  def clean_scopes(request_id,
                   raw_scopes,
                   global_allowed_scopes,
                   client_config,
                   require_openid: true)
    rlog.info("[#{request_id}] Raw incoming scopes: #{raw_scopes.inspect}")
    scopes = raw_scopes.split.to_set

    if require_openid && !scopes.include?('openid')
      rlog.error("[#{request_id}] No \"openid\" found in scopes")
      return { success: false }
    end

    original = scopes.dup

    # Remove scopes that aren't allowed for this client
    client_allowed = (['openid'] + client_config.fetch('allowed_scopes', [])).to_set
    scopes &= client_allowed
    rlog.info("[#{request_id}] Partially cleaned-up scopes: #{scopes.to_a.inspect}")

    # Remove unknown scopes
    scopes &= global_allowed_scopes
    rlog.info("[#{request_id}] Final cleaned-up scopes: #{scopes.to_a.inspect}")

    # We need to inform the client if the final scopes are different than what it sent
    # (RFC 6749 section 3.3.)
    changed = scopes != original

    if changed
      rlog.info("[#{request_id}] The scopes did change, informing the client")
    end

    {
      success: true,
      scopes: scopes.to_a,
      changed: changed
    }
  rescue StandardError => e
    rlog.info("[#{request_id}] Could not clean up the scopes: #{e}")
    { success: false }
  end
end   # module OAuth2
end   # module PuavoRest
