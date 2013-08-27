class ExternalApplication < LdapBase
  ldap_mapping(
    :dn_attribute => "puavoServiceDomain",
    :prefix => "ou=Services"
  )
end
