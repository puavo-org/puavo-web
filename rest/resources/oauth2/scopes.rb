# frozen_string_literal: true

# OAuth2 and OpenID Connect scopes

module PuavoRest
module OAuth2

module Scopes

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
  puavo.read.userinfo.primus
  puavo.read.userinfo.mpassid
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

# The return value of clean_scopes()
CleanedScopes = Struct.new(
  :scopes,      # the valid scopes
  :success,     # false if something went wrong
  :changed,     # true if the returned scopes are different from the raw scopes
  keyword_init: true
)

# Parses a string containing scopes separated by spaces, and removes invalid scopes
# and scopes that aren't allowed for this client. Returns a CleanedScopes struct.
def self.clean_scopes(request_id, raw_scopes, global_allowed_scopes, client_config, require_openid: true)
  $rest_log.info("[#{request_id}] Raw incoming scopes: #{raw_scopes.inspect}")
  scopes = raw_scopes.split.to_set

  if require_openid && !scopes.include?('openid')
    $rest_log.error("[#{request_id}] No \"openid\" found in scopes")
    return CleanedScopes.new(success: false)
  end

  original = scopes.dup

  # Remove scopes that aren't allowed for this client
  client_allowed = (['openid'] + client_config.fetch('allowed_scopes', [])).to_set
  scopes &= client_allowed
  $rest_log.info("[#{request_id}] Partially cleaned-up scopes: #{scopes.to_a.inspect}")

  # Remove unknown scopes
  scopes &= global_allowed_scopes
  $rest_log.info("[#{request_id}] Final cleaned-up scopes: #{scopes.to_a.inspect}")

  # We need to inform the client if the final scopes are different than what it sent
  # (RFC 6749 section 3.3.)
  changed = scopes != original

  if changed
    $rest_log.info("[#{request_id}] The scopes did change, informing the client")
  end

  CleanedScopes.new(scopes: scopes, success: true, changed: changed)
rescue StandardError => e
  $rest_log.info("[#{request_id}] Could not clean up the scopes: #{e}")
  CleanedScopes.new(success: false)
end

end   # module Scopes

end   # module OAuth2
end   # module PuavoRest
