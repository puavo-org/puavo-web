module PuavoRest
class School < LdapHash
  ldap_map :dn, :dn
  ldap_map :puavoDeviceImage, :preferred_image
  ldap_map(:puavoWlanSSID, :wlan_networks) do |networks|
    networks.map { |n| JSON.parse(n) }
  end
end
end
