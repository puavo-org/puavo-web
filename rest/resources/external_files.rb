module PuavoRest

class ExternalFile < LdapModel

  ldap_map :cn, :name
  ldap_map :puavoDataHash, :data_hash

  def self.ldap_base
    "ou=Files,ou=Desktops,#{ organisation["base"] }"
  end

  def self.base_filter
    "(&(objectClass=top)(objectClass=puavoFile))"
  end

  # return file contents for file name
  def self.data_only(name)
    res = by_attr!(:name, name, {
      :raw => true,
      :ldap_attrs => [:puavoData]
    })
     Array(res["puavoData"]).first
  end

end


# External Files saved in LDAP
class ExternalFiles < PuavoSinatra

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
    auth :basic_auth, :server_auth, :legacy_server_auth

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
    auth :basic_auth, :server_auth, :legacy_server_auth

    json ExternalFile.by_attr!(:name, params[:name])
  end

  # Get file contents
  # @!macro route
  get "/v3/external_files/:name" do
    auth :basic_auth, :server_auth, :legacy_server_auth

    content_type "application/octet-stream"
    ExternalFile.data_only(params[:name])
  end

  # Get metadata list of external files by device hostname
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
  get "/v3/devices/:hostname/external_files" do
    auth :basic_auth, :server_auth, :legacy_server_auth

    printer_ppd_data_hash = nil
    device = Device.by_hostname(params[:hostname])

    if device
      if device.printer_ppd
        printer_ppd_data_hash = Digest::SHA1.new
        printer_ppd_data_hash.update(device.printer_ppd)
      end
    end

    external_files = ExternalFile.all

    if printer_ppd_data_hash
      external_files.push(
        {"name" => "printer.ppd", "data_hash" => printer_ppd_data_hash.to_s }
      )
    end

    json external_files
  end

  # Get file contents by device hostname
  # @!macro route
  get "/v3/devices/:hostname/external_files/:name" do
    auth :basic_auth, :server_auth, :legacy_server_auth

    content_type "application/octet-stream"

    if params[:name] == "printer.ppd"
      if device = Device.by_hostname(params[:hostname])
        device.printer_ppd
      end
    else
      ExternalFile.data_only(params[:name])
    end
  end

end
end
