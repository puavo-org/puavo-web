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


  def self.find_or_create(user_dn, oauth_client_server_dn)
    self.find(:first,
      :attribute => "puavoOAuthEduPerson",
      :value => user_dn) || self.new(
        :puavoOAuthEduPerson => user_dn,
        :puavoOAuthClient => oauth_client_server_dn
    )
  end

end
