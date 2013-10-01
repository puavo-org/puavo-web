module PuavoRest
class BootServer < LdapHash

  ldap_map :dn, :dn
  ldap_map :puavoHostname, :hostname

  def self.ldap_base
    "ou=Servers,ou=Hosts,#{ organisation["base"] }"
  end

end
end
