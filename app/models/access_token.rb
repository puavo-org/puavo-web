require "oauth_helpers"

class AccessToken < LdapBase
  include Puavo::Security
  include OAuthHelpers

  LIFETIME = 5.days

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
  def self.find_or_create(user_dn, oauth_client_server_dn)

    filter = "(&(puavoOAuthEduPerson=#{ user_dn })(puavoOAuthClient=#{ oauth_client_server_dn }))"

    results = self.search(
      :filter => filter,
      :attributes => "dn"
    )

    if results.empty?
      return self.new(
        :puavoOAuthEduPerson => user_dn,
        :puavoOAuthClient => oauth_client_server_dn)
    end

    if results.size > 1
      raise "#{ user_dn } has more than one AccessTokens to #{ oauth_client_server_dn }"
    end

    access_token_dn = ActiveLdap::DistinguishedName.parse results.first.first
    return self.find(access_token_dn)
  end

end
