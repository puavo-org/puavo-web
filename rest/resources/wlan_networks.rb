require_relative "./devices"

module PuavoRest
class WlanNetworks < LdapSinatra

  auth Credentials::BootServer

  def networks
    device = Device.by_hostname(params["hostname"])
    return (
      Array(device.organisation["wlan_networks"]) +
      Array(device.school["wlan_networks"])
    )
  end

  get "/v3/devices/:hostname/wlan_networks" do
    json networks
  end

  get "/v3/devices/:hostname/wlan_hotspot_configurations" do
    # TODO: should be only served to fatclients
    json(networks.select do |wlan|
      wlan["wlan_ap"]
    end)
  end

end
end
