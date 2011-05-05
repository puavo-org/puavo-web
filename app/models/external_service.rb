class ExternalService < LdapBase
  ldap_mapping( :dn_attribute => "uid",
                :prefix => "ou=System Accounts",
                :classes => ["simpleSecurityObject", "account"] )
end
