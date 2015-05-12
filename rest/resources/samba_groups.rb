

module PuavoRest

class SambaGroup < LdapModel

  ldap_map :dn, :dn
  ldap_map :cn, :name
  ldap_map :memberUid, :members, LdapConverters::ArrayValue

  def self.ldap_base
    "ou=Groups,#{ organisation["base"] }"
  end

  # This will return all groups including the standard groups (see groups.rb)
  # as they both have sambaGroupMapping object class.
  def self.base_filter
    "(objectClass=sambaGroupMapping)"
  end

end
end
