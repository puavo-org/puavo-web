class OauthClient < LdapBase
  ldap_mapping( :dn_attribute => "puavoOAuthClientId",
                :prefix => "ou=Clients,ou=OAuth",
                :classes => ["simpleSecurityObject", "puavoOAuthClient"] )
end
