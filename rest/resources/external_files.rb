module PuavoRest


class ExternalFilesModel < LdapModel

  ldap_attr_conversion :cn, :name
  ldap_attr_conversion :puavoDataHash, :data_hash

  def ldap_base
    "ou=Files,ou=Desktops,#{ @organisation_info["base"] }"
  end

  def index
    filter(
      "(&(objectClass=top)(objectClass=puavoFile))",
      ExternalFilesModel.ldap_attrs
    ).map do |entry|
      ExternalFilesModel.convert(entry)
    end
  end

  def file_filter(name)
    name = LdapModel.escape(name)
    "(&(cn=#{ name })(objectClass=top)(objectClass=puavoFile))"
  end

  def metadata(name)
    ExternalFilesModel.convert filter(
      file_filter(name),
      ExternalFilesModel.ldap_attrs
    ).first
  end

  def data(name)
    name = LdapModel.escape(name)
    filter(file_filter(name), ["puavoData"]).first["puavoData"]
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
  get "/v3/:organisation/external_files" do
    json new_model(ExternalFilesModel).index
  end

  # Get metadata for external file
  #
  #    {
  #      "name": <filename>,
  #      "data_hash": <sha1 checksum of the file>
  #    }
  # @!macro route
  get "/v3/:organisation/external_files/:name/metadata" do
    json new_model(ExternalFilesModel).metadata(params[:name])
  end

  # Get file contents
  # @!macro route
  get "/v3/:organisation/external_files/:name" do
    content_type "application/octet-stream"
    new_model(ExternalFilesModel).data(params[:name])
  end

end
end
