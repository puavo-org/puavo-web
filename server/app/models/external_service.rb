class ExternalService < LdapBase
  include Puavo::AuthenticationMixin

  ldap_mapping( :dn_attribute => "uid",
                :prefix => "ou=System Accounts",
                :classes => ["simpleSecurityObject", "account"] )
end
