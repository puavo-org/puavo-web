module PuavoRest
class School < LdapModel

  ldap_map :dn, :dn
  ldap_map :puavoId, :puavo_id
  ldap_map :displayName, :name
  ldap_map :puavoDeviceImage, :preferred_image
  ldap_map(:puavoPrinterQueue, :printer_queue_dns){ |v| Array(v) }
  ldap_map(:puavoWirelessPrinterQueue, :wireless_printer_queue_dns){ |v| Array(v) }
  ldap_map :preferredLanguage, :preferred_language
  ldap_map :puavoWlanSSID, :wlan_networks, &LdapConverters.parse_wlan
  ldap_map :puavoAllowGuest, :allow_guest, &LdapConverters.string_boolean
  ldap_map :puavoPersonalDevice, :personal_device, &LdapConverters.string_boolean
  ldap_map(:puavoActiveService, :external_services) do |es|
      Array(es).map { |s| s.downcase.strip }
  end

  def self.ldap_base
    "ou=Groups,#{ organisation["base"] }"
  end

  def self.base_filter
    "(objectClass=puavoSchool)"
  end

  def printer_queues
    @printer_queues ||= PrinterQueue.by_dn_array(printer_queue_dns)
  end

  def wireless_printer_queues
    @wireless_printer_queues ||= PrinterQueue.by_dn_array(wireless_printer_queue_dns)
  end

  # Cached organisation query
  def organisation
    @organisation ||= Organisation.by_dn(self.class.organisation["base"])
  end


  def preferred_image
     if get_own(:preferred_image).nil?
       organisation.preferred_image
      else
        get_own(:preferred_image)
      end
  end

  def allow_guest
     if get_own(:allow_guest).nil?
       organisation.allow_guest
     else
       get_own(:allow_guest)
     end
  end

  def personal_device
     if get_own(:personal_device).nil?
       organisation.personal_device
     else
       get_own(:personal_device)
     end
  end

  def preferred_language
    if get_own(:preferred_language).nil?
      organisation.preferred_language
    else
      get_own(:preferred_language)
    end
  end

end
end
