class ExternalService < LdapBase
  include Puavo::Authentication

  ldap_mapping( :dn_attribute => "uid",
                :prefix => "ou=System Accounts",
                :classes => ["simpleSecurityObject", "account"] )
end
