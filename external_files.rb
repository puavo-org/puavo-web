
module PuavoRest

class ExternalFiles < LdapBase

  # use BasicAuthCredentials
  use ServerCredentials

  def ldap_base
    # XXX: Escape!
    "ou=Files,ou=Desktops,dc=edu,dc=#{ params["organisation"] },dc=fi"
  end

  get "/:organisation/external_files" do

    external_files = []
    @ldap_conn.search(ldap_base, LDAP::LDAP_SCOPE_SUBTREE, "(&(objectClass=top)(objectClass=puavoFile))", [
      "cn", "puavoDataHash"
    ]) do |entry|
      external_files.push({
        "name" => entry.vals("cn").first,
        "data_hash" => entry.vals("puavoDataHash").first,
      })
    end
    json external_files
  end

end
end
