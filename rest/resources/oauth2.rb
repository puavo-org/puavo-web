# frozen_string_literal: true

# OpenID Connect SSO system, and OAuth2 client credentials token generation

require_relative '../lib/login/utility'

require_relative 'oauth2/helpers'
require_relative 'oauth2/scopes'
require_relative 'oauth2/authorization_code'
require_relative 'oauth2/client_credentials'
require_relative 'oauth2/access_token'
require_relative 'oauth2/userinfo'

module PuavoRest
module OAuth2

# RFC 9207 issuer identifier
ISSUER = 'https://auth.opinsys.fi'

class OAuth2Endpoints < PuavoSinatra
  register Sinatra::R18n

  include PuavoLoginUtility
  include PuavoLoginSession

  include OAuth2

  # OpenID Connect Stage 1 (authorization request)
  # Accept both GET and POST requests. RFC 6749 says GET requests MUST be supported, while
  # POST requests MAY be supported.
  get '/oidc/authorize' do
    oidc_stage1_authorization_request
  end

  post '/oidc/authorize' do
    oidc_stage1_authorization_request
  end

  # OpenID Connect Stage 2 (authorization response)
  get '/oidc/authorize/response' do
    oidc_stage2_authorization_response
  end

  # OIDC ID token / client credentials access token generation
  # (OpenID Connect Stage 3)
  post '/oidc/token' do
    # What kind of a request are we dealing with? We must create a temporary request ID
    # because we cannot access the stored data before validation.
    temp_request_id = make_request_id
    grant_type = params.fetch('grant_type', nil)
    rlog.info("[#{temp_request_id}] OAuth2 token request, grant type: #{grant_type.inspect}")

    case grant_type
      when 'authorization_code'
        oidc_stage3_access_token_request(temp_request_id)

      when 'client_credentials'
        client_credentials_grant(temp_request_id)

      else
        rlog.error("[#{temp_request_id}] Unsupported grant type")
        json_error('unsupported_grant_type', request_id: temp_request_id)
    end
  end

  # OpenID Connect userinfo endpoint. Only OAuth2 access token logins are supported.
  # This is the only place where the access token generated during logins can be used in.
  # https://openid.net/specs/openid-connect-core-1_0.html#UserInfo says we MUST support
  # both GET and POST userinfo requests.
  get '/oidc/userinfo' do
    oidc_handle_userinfo
  end

  post '/oidc/userinfo' do
    oidc_handle_userinfo
  end

  # OpenID Connect SSO session logout
  get '/oidc/authorize/logout' do
    session_try_logout
  end
end   # class OAuth2Endpoints

end   # module OAuth2
end   # module PuavoRest
