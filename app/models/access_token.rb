class AccessToken < LdapBase
  include Puavo::Security
  LIFETIME = 5.days

  ldap_mapping( :dn_attribute => "puavoOAuthTokenId",
                :prefix => "ou=Tokens,ou=OAuth",
                :classes => ["simpleSecurityObject", "puavoOAuthAccessToken"] )

  before_save :encrypt_userPassword

end
