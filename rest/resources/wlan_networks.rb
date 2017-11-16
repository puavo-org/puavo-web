require_relative "./devices"

module PuavoRest
class WlanNetworks < PuavoSinatra

  def networks
    device = Device.by_hostname(params["hostname"])

    if device.nil? then
      status 404
      return json({ :status => "failed",
                    :error  => "Cannot find device by hostname" })
    end

    org_networks = Array(device.organisation["wlan_networks"])
    school_networks = Array(device.school["wlan_networks"])

    school_networks_ssids = school_networks.map { |w| w["ssid"] }
    org_networks.delete_if { |w| school_networks_ssids.include?(w["ssid"]) }

    return org_networks + school_networks
  end

  get "/v3/devices/:hostname/wlan_networks" do
    auth :basic_auth, :server_auth, :legacy_server_auth

    only_open_and_psk_networks \
      = networks.select { |s| %w(open psk).include?(s['type']) }

    json only_open_and_psk_networks
  end

  get "/v3/devices/:hostname/wlan_networks_with_certs" do
    # Networks might include "eap-tls" and other networks that require
    # certificates, so keep this information more secret than other network
    # secrets.  Netboot devices should have no need for this information.
    auth :basic_auth

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
