class ConfigurationFile < LdapBase
  ldap_mapping( :dn_attribute => "puavoFileId",
                :prefix => "ou=Files,ou=Desktops",
                :classes => ["puavoFile"] )

end
