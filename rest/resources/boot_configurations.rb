
module PuavoRest
class BootConfigurations < LdapSinatra

  def host_by_mac_address(mac_address)
    host = PuavoRest::Host.by_mac_address(mac_address)
    if host.type == "ltspserver"
      LtspServer.by_dn(host.dn)
    else
      Device.by_dn(host.dn)
    end
  end

  get "/v3/:mac_address/boot_configuration" do
    auth :server_auth

    # Get Device or LtspServer
    host = host_by_mac_address(params["mac_address"])
    host.grub_boot_configuration

  end

end
end
