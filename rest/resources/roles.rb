module PuavoRest

class Role < LdapModel
  ldap_map :dn, :dn
  ldap_map :displayName, :name
  ldap_map :puavoId, :id

  def self.ldap_base
    "ou=Roles,#{ organisation["base"] }"
  end

  def self.by_user_dn(dn)
    filter("(member=#{ escape dn })")
  end

end
end
