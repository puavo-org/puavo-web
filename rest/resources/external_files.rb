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

  def self.raw_list
    ExternalFile.raw_filter(self.ldap_base(),
                            self.base_filter(),
                            ['cn', 'puavoDataHash']).collect do |file|
      {
        name: file['cn'][0],
        data_hash: file['puavoDataHash'][0],
      }
    end
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

    json ExternalFile.raw_list
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

    external_files = ExternalFile.raw_list

    # If the device has a printer driver, manually append
    # its file to the external files list
    raw_device = Device.by_hostname_raw_attrs(params[:hostname], ['puavoPrinterPPD'])

    if raw_device.count == 1 && raw_device[0].include?('puavoPrinterPPD')
      printer_ppd_data_hash = Digest::SHA1.new
      printer_ppd_data_hash.update(raw_device[0]['puavoPrinterPPD'][0].to_s)

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

    # Manually handle the printer driver file
    if params[:name] == "printer.ppd"
      raw_device = Device.by_hostname_raw_attrs(params[:hostname], ['puavoPrinterPPD'])

      if raw_device.count == 1 && raw_device[0].include?('puavoPrinterPPD')
        raw_device[0]['puavoPrinterPPD']
      end
    else
      ExternalFile.data_only(params[:name])
    end
  end

end
end
