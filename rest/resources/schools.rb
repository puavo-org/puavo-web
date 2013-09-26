module PuavoRest
class School < LdapHash

  ldap_map :dn, :dn
  ldap_map :puavoId, :puavo_id
  ldap_map :displayName, :name
  ldap_map :puavoDeviceImage, :preferred_image
  ldap_map :puavoPrinterQueue, :printer_queue_dns
  ldap_map :puavoWirelessPrinterQueue, :wireless_printer_queue_dns
  ldap_map :puavoWlanSSID, :wlan_networks, &LdapConverters.parse_wlan
  ldap_map :puavoAllowGuest, :allow_guest, &LdapConverters.string_boolean
  ldap_map :puavoPersonalDevice, :personal_device, &LdapConverters.string_boolean
  ldap_map(:puavoActiveService, :external_services) do |es|
      Array(es).map { |s| s.downcase.strip }
  end

  def printer_queues
    Array(self["printer_queue_dns"]).map do |dn|
      PrinterQueue.by_dn(dn)
    end
  end

  def wireless_printer_queues
    Array(self["wireless_printer_queue_dns"]).map do |dn|
      PrinterQueue.by_dn(dn)
    end
  end

end
end
