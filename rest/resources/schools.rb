module PuavoRest
class School < LdapHash

  # Parse wlan data from puavoWlanSSID attribute
  def self.parse_wlan(networks)
    networks.map do |n|
      begin
        JSON.parse(n)
      rescue JSON::ParserError
        # Legacy data is not JSON. Just ignore...
      end
    end.compact
  end

  ldap_map :dn, :dn
  ldap_map :puavoDeviceImage, :preferred_image
  ldap_map :puavoWlanSSID, :wlan_networks, &method(:parse_wlan)
  ldap_map :puavoAllowGuest, :allow_guest
end
end
