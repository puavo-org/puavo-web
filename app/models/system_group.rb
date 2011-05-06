class SystemGroup < LdapBase
  ldap_mapping( :dn_attribute => "cn",
                :prefix => "ou=System Groups",
                :classes => ["top", "puavoSystemGroup"] )

  has_many :members, :class_name => "ExternalService", :wrap => "member", :primary_key => "dn"
end
