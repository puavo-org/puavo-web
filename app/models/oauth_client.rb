class OauthClient < LdapBase
  include Puavo::Security

  ldap_mapping( :dn_attribute => "puavoOAuthClientId",
                :prefix => "ou=Clients,ou=OAuth",
                :classes => ["simpleSecurityObject", "puavoOAuthClient"] )

  before_validation  :generate_puavoOAuthClientId, :set_client_type
  before_save :encrypt_userPassword

  private

  def generate_puavoOAuthClientId
    self.puavoOAuthClientId = UUID.new.generate if self.puavoOAuthClientId.nil?
  end

  def set_client_type
    self.puavoOAuthClientType = 'confidential'
  end
end
