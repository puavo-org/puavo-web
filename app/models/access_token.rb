require "oauth_helpers"

class AccessToken < LdapBase
  include Puavo::Security
  include OAuthHelpers

  LIFETIME = 1.hour

  ldap_mapping( :dn_attribute => "puavoOAuthTokenId",
                :prefix => "ou=Tokens,ou=OAuth",
                :classes => ["simpleSecurityObject", "puavoOAuthAccessToken"] )

  before_save :encrypt_userPassword


  class Expired < UserError
    attr_accessor :token
    def initialize(message, token)
      super message
      @token = token
    end
  end


  # Return new or existing AccessToken entry with given user_dn and
  # oauth_client_server_dn
  def self.find_or_create(user_dn, oauth_client_server_dn, oauth_scope)

    filter = "(&(puavoOAuthEduPerson=#{ user_dn })(puavoOAuthClient=#{ oauth_client_server_dn }))"

    results = self.search_as_utf8(
      :filter => filter,
      :attributes => "dn"
    )

    if results.empty?
      return self.new(
        :puavoOAuthEduPerson => user_dn,
        :puavoOAuthClient => oauth_client_server_dn,
        :puavoOAuthScope => oauth_scope )
    end

    if results.size > 1
      raise "#{ user_dn } has more than one AccessTokens for #{ oauth_client_server_dn }"
    end

    access_token_dn = ActiveLdap::DistinguishedName.parse results.first.first
    access_token_entry = self.find(access_token_dn)
    access_token_entry.puavoOAuthScope = oauth_scope
    access_token_entry.save!
    return access_token_entry
  end

end
