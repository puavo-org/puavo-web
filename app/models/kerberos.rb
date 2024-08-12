class Kerberos < LdapBase
  ldap_mapping(:dn_attribute => 'krbPrincipalName',
               :prefix       => 'ou=Kerberos Realms',
               :classes      => [ 'krbPrincipal' ])
end
