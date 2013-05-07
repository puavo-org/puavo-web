module PuavoRest
# External Files saved in LDAP
class ExternalFiles < LdapSinatra

  use Credentials::BasicAuth
  use Credentials::BootServer

  def ldap_base
    # XXX: Escape!
    "ou=Files,ou=Desktops,dc=edu,dc=#{ params["organisation"] },dc=fi"
  end

  # Get metadata list of external files
  #    [
  #      {
  #        "name": <filename>,
  #        "data_hash": <sha1 checksum of the file>
  #      },
  #      ...
  #    ]
  #
  # @!macro route
  # @param foo
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

  # Get file contents
  # @!macro route
  get "/:organisation/external_files/:name" do
    # TODO
  end

end
end
