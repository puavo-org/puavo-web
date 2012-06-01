class OauthClient < LdapBase
  include Puavo::Security

  ldap_mapping( :dn_attribute => "puavoOAuthClientId",
                :prefix => "ou=Clients,ou=OAuth",
                :classes => ["simpleSecurityObject", "puavoOAuthClient"] )

  before_validation  :generate_puavoOAuthClientId
  before_save :encrypt_userPassword

  private

  def generate_puavoOAuthClientId
    self.puavoOAuthClientId = "oauth_client_id/" + UUID.new.generate
  end
end
