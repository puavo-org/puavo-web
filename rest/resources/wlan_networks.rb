require_relative "./devices"

module PuavoRest
class WlanNetworks < PuavoSinatra

  def parse_json_array(value)
    Array(value).map do |n|
      begin
        JSON.parse(n)
      rescue JSON::ParserError
        JSON::ParserError
      end
    end.select{|v| v != JSON::ParserError}
  end

  def networks
    # Check that the device exists, then find its school for the WLAN settings
    device = Device.by_hostname_raw_attrs(params['hostname'], ['puavoSchool'])

    if device.count != 1
      raise NotFound, :user => 'Cannot find device by hostname'
    end

    school = School.by_dn_raw_attrs(device[0]['puavoSchool'][0], ['puavoWlanSSID'])

    if school.nil?
      school_networks = []
    else
      school_networks = parse_json_array(school.fetch('puavoWlanSSID', []))
    end

    # Get the current organsation WLAN definitions. Our organisation cache is bugged,
    # so query the database directly.
    organisation = []

    Organisation.connection.search(
      Organisation.current.dn, LDAP::LDAP_SCOPE_BASE, '(objectclass=*)', ['puavoWlanSSID']) do |org|
      organisation << org.to_hash
    end

    if organisation.count == 1
      org_networks = parse_json_array(organisation[0].fetch('puavoWlanSSID', []))
    else
      # Okay. Right. Whatever. Use the cached value then and hope for the best.
      org_networks = Array(Organisation.current.wlan_networks)
    end

    # Allow schools to override organisation-level networks
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
