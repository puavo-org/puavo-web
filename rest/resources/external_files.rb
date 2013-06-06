module PuavoRest

class ExternalFile < LdapHash

  ldap_map :cn, :name
  ldap_map :puavoDataHash, :data_hash

  def self.ldap_base
    "ou=Files,ou=Desktops,#{ organisation["base"] }"
  end

  def self.all
    filter("(&(objectClass=top)(objectClass=puavoFile))")
  end

  def self.file_filter(name)
    name = LdapModel.escape(name)
    "(&(cn=#{ name })(objectClass=top)(objectClass=puavoFile))"
  end

  # return file metadata for file name
  def self.metadata(name)
    filter(file_filter(name)).first
  end

  # return file contents for file name
  def self.data_only(name)
    name = LdapModel.escape(name)
    raw_filter(file_filter(name), ["puavoData"]).first["puavoData"]
  end

end


# External Files saved in LDAP
class ExternalFiles < LdapSinatra

  auth Credentials::BasicAuth
  auth Credentials::BootServer

  # Get metadata list of external files
  #
  #    [
  #      {
  #        "name": <filename>,
  #        "data_hash": <sha1 checksum of the file>
  #      },
  #      ...
  #    ]
  #
  # @!macro route
  get "/v3/external_files" do
    json ExternalFile.all
  end

  # Get metadata for external file
  #
  #    {
  #      "name": <filename>,
  #      "data_hash": <sha1 checksum of the file>
  #    }
  # @!macro route
  get "/v3/external_files/:name/metadata" do
    json ExternalFile.metadata(params[:name])
  end

  # Get file contents
  # @!macro route
  get "/v3/external_files/:name" do
    content_type "application/octet-stream"
    ExternalFile.data_only(params[:name])
  end

end
end
