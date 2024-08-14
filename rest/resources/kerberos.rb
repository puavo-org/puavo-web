module PuavoRest

class Kerberos < LdapModel
  ldap_map :dn, :dn
  ldap_map :krbLastSuccessfulAuth, :krb_last_successful_auth
  ldap_map :krbPrincipalName, :krb_principal_name

  def self.ldap_base
    "ou=Kerberos Realms,#{ organisation["base"] }"
  end
end
end
