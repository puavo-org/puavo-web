
module PuavoRest
class BootConfigurations < LdapSinatra

  def host_by_mac_address!(mac_address)
    host = PuavoRest::Host.by_mac_address!(mac_address)
    if host.type == "ltspserver"
      LtspServer.by_dn(host.dn)
    else
      Device.by_dn(host.dn)
    end
  end

  get "/v3/:mac_address/boot_configuration" do
    auth :server_auth

    # Get Device or LtspServer
    begin
      host = host_by_mac_address!(params["mac_address"])
    rescue NotFound => e
      # Create dummy host object for getting boot configuration to unregistered device
      host = PuavoRest::LtspServer.new
    end
    host.grub_boot_configuration

  end

end
end
