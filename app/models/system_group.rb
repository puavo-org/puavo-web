class SystemGroup < LdapBase
  ldap_mapping( :dn_attribute => "cn",
                :prefix => "ou=System Groups",
                :classes => ["puavoSystemGroup"] )

  has_many :members, :class_name => "LdapService", :wrap => "member", :primary_key => "dn"
end
