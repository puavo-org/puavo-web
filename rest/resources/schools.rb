module PuavoRest
class School < LdapHash

  ldap_map :dn, :dn
  ldap_map :puavoDeviceImage, :preferred_image
  ldap_map :puavoWlanSSID, :wlan_networks, &LdapConverters.parse_wlan
  ldap_map :puavoAllowGuest, :allow_guest, &LdapConverters.string_boolean
  ldap_map :puavoPersonalDevice, :personal_device, &LdapConverters.string_boolean
  ldap_map(:puavoActiveService, :external_services){ |v| Array(v) }

end
end
