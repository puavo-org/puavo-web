require_relative "../local_store"

module PuavoRest
class School < LdapModel
  include LocalStore

  ldap_map :dn, :dn
  ldap_map :puavoId, :puavo_id
  ldap_map :displayName, :name
  ldap_map :puavoDeviceImage, :preferred_image
  ldap_map :puavoSchoolHomePageURL, :homepage
  ldap_map(:puavoPrinterQueue, :printer_queue_dns){ |v| Array(v) }
  ldap_map(:puavoWirelessPrinterQueue, :wireless_printer_queue_dns){ |v| Array(v) }
  ldap_map :preferredLanguage, :preferred_language
  ldap_map(:puavoExternalFeed, :external_feeds, &LdapConverters.json)
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
        get_own(:preferred_image).strip
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

  def ical_feed_urls
    Array(external_feeds).select do |feed|
      feed["type"] == "ical"
    end.map do |feed|
      feed["value"]
    end
  end

  def cache_feeds
    ical_feed_urls.each do |url|
      begin
        res = HTTParty.get(url)
      rescue Exception => err
        $rest_flog.error "Failed to fetch ical",
          :url => url,
          :error => err.message
        next
      end

      local_store.set("feed:#{ url }", res)
      # Max cache for 12h
      local_store.expire("feed:#{ url }", 60 * 60 * 12)
    end
  end

  computed_attr :messages
  def messages
    ical_feed_urls.map do |url|
      if data = local_store.get("feed:#{ url }")
        begin
          ICALParser.parse(data).current_events
        rescue Exception => err
          $rest_flog.error "Failed to parse ical",
            :data => data.to_s.slice(0, 100),
            :error => err.message
        end
      end
    end.compact.flatten
  end

end
end
