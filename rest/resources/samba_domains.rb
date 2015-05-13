
module PuavoRest

class SambaDomain < LdapModel

  ldap_map :dn, :dn
  ldap_map :puavoId, :id
  ldap_map :sambaSID, :sid
  ldap_map :sambaDomainName, :domain
  ldap_map :sambaNextRid, :legacy_rid

  def self.ldap_base
    organisation["base"]
  end

  def self.base_filter
    "(objectClass=sambaDomain)"
  end

end
end
