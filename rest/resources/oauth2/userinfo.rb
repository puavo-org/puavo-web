# frozen_string_literal: true

# OpenID Connect userinfo handling

require_relative 'id_token'

module PuavoRest
module OAuth2
module Userinfo
  # Handles the OpenID Connect userinfo request
  def userinfo_request
    oauth2 scopes: %w[openid profile], audience: 'puavo-rest-userinfo'
    auth :oauth2_token

    request_id = make_request_id

    begin
      # Since only a OAuth2 access token authentication is possible, this can never be nil
      access_token = LdapModel.settings[:credentials][:access_token]

      rlog.info("[#{request_id}] Returning userinfo data for user \"#{access_token['user_dn']}\" " \
                "in organisation \"#{access_token['organisation_domain']}\"")

      out = IDTokenDataGenerator.new(request_id).generate(
        ldap_credentials: {
          dn: CONFIG['oauth2']['userinfo_dn'],
          password: CONFIG['oauth2']['ldap_accounts'][CONFIG['oauth2']['userinfo_dn']]
        },
        domain: access_token['organisation_domain'],
        user_dn: access_token['user_dn'],
        scopes: access_token['scopes'].split,
        auth_method: nil,
        include_sub: true
      )

      json_error(out, request_id: request_id) if out.instance_of?(String)

      headers['Cache-Control'] = 'no-store'
      headers['Pragma'] = 'no-cache'
      json(out)
    rescue StandardError => e
      rlog.error("[#{request_id}] Could not gather the user data: #{e}")
      json_error('server_error', request_id: request_id)
    end
  end
end
end   # module OAuth2
end   # module PuavoRest
