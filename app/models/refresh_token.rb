class RefreshToken < LdapBase

ldap_mapping( :dn_attribute => "puavoOAuthTokenId",
              :prefix => "ou=Tokens,ou=OAuth",
              :classes => ["simpleSecurityObject", "puavoOAuthRefreshToken"] )


end
