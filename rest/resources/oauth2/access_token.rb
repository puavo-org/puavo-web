# OAuth2 access token generation

require 'securerandom'
require 'openssl'
require 'jwt'

module PuavoRest
module OAuth2
  def build_access_token(request_id,
                         scopes: [],
                         client_id: nil,
                         subject: nil,
                         audience: 'puavo-rest-v4',
                         expires_in: 3600,
                         custom_claims: nil)
    now = Time.now.utc.to_i

    token_claims = {
      'jti' => SecureRandom.uuid,
      'iat' => now,
      'nbf' => now,
      'exp' => now + expires_in,
      'iss' => ISSUER,
      'sub' => subject,
      'aud' => audience,
      'scopes' => scopes.join(' '),
    }

    if client_id
      token_claims['client_id'] = client_id
    end

    if custom_claims && custom_claims.is_a?(Hash)
      token_claims.merge!(custom_claims)
    end

    # Load the signing private key. Unlike the public key, this is not kept in memory.
    begin
      private_key = OpenSSL::PKey.read(File.open(CONFIG['oauth2_token_private_key']))
    rescue StandardError => e
      rlog.error("[#{request_id}] Cannot load the access token signing private key file: #{e}")
      return { success: false }
    end

    # TODO: Support encrypted tokens with JWE? The "jwe" gem is already installed.
    # TODO: Install the jwt-eddsa gem and use EdDSA signing? Is it compatible with JWT?

    # Sign the token data using the private key. RFC 9068 section 2.1. says the "typ" value
    # SHOULD be "at+jwt", but the JWT gem does not set it, so let's set it manually.
    # (I have no idea what I'm doing.)
    access_token = JWT.encode(token_claims, private_key, 'ES256', { typ: 'at+jwt' })

    {
      success: true,
      access_token: access_token,
      jti: token_claims['jti'],
      expires_at: now + expires_in
    }
  end
end   # module OAuth2
end   # module PuavoRest
