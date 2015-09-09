require_relative "./devices"

module PuavoRest
class WlanNetworks < PuavoSinatra

  def networks
    device = Device.by_hostname(params["hostname"])

    org_networks = Array(device.organisation["wlan_networks"])
    school_networks = Array(device.school["wlan_networks"])

    school_networks_ssids = school_networks.map{ |w| w["ssid"] }
    org_networks.delete_if{ |w| school_networks_ssids.include?(w["ssid"]) }

    return org_networks + school_networks
  end

  get "/v3/devices/:hostname/wlan_networks" do
    auth :basic_auth, :server_auth, :legacy_server_auth

    json networks
  end

  get "/v3/devices/:hostname/wlan_hotspot_configurations" do
    auth :basic_auth, :server_auth, :legacy_server_auth

    # TODO: should be only served to fatclients
    json(networks.select do |wlan|
      wlan["wlan_ap"]
    end)
  end

end
end
