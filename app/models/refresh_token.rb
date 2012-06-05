class RefreshToken < LdapBase
  include Puavo::Security
  LIFETIME = 6.months


  ldap_mapping( :dn_attribute => "puavoOAuthTokenId",
              :prefix => "ou=Tokens,ou=OAuth",
              :classes => ["simpleSecurityObject", "puavoOAuthRefreshToken"] )

  before_save :encrypt_userPassword


end
