class AccessToken < LdapBase
  include Puavo::Security

  ldap_mapping( :dn_attribute => "puavoOAuthAccessTokenId",
                :prefix => "ou=Tokens,ou=OAuth",
                :classes => ["simpleSecurityObject", "puavoOAuthAccessToken"] )

  before_save :encrypt_userPassword

end
