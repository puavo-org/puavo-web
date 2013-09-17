require_relative "./devices"

module PuavoRest
class WlanNetworks < LdapSinatra

  def networks
    device = Device.by_hostname(params["hostname"])
    return (
      Array(device.organisation["wlan_networks"]) +
      Array(device.school["wlan_networks"])
    )
  end

  get "/v3/devices/:hostname/wlan_networks" do
    auth :basic_auth, :server_auth

    json networks
  end

  get "/v3/devices/:hostname/wlan_hotspot_configurations" do
    auth :basic_auth, :server_auth

    # TODO: should be only served to fatclients
    json(networks.select do |wlan|
      wlan["wlan_ap"]
    end)
  end

end
end
