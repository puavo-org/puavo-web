class OauthClient < LdapBase
  include Puavo::Security

  ldap_mapping( :dn_attribute => "puavoOAuthClientId",
                :prefix => "ou=Clients,ou=OAuth",
                :classes => ["simpleSecurityObject", "puavoOAuthClient"] )

  before_save :encrypt_userPassword

end
