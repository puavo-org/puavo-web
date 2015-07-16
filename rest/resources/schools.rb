require_relative "../lib/local_store"

module PuavoRest
class School < LdapModel
  include LocalStore

  ldap_map :dn, :dn
  ldap_map :puavoId, :id, LdapConverters::Number
  ldap_map :objectClass, :object_classes, LdapConverters::ArrayValue
  ldap_map :displayName, :name
  ldap_map :puavoDeviceImage, :preferred_image
  ldap_map :puavoSchoolHomePageURL, :homepage
  ldap_map(:puavoPrinterQueue, :printer_queue_dns){ |v| Array(v) }
  ldap_map(:puavoWirelessPrinterQueue, :wireless_printer_queue_dns){ |v| Array(v) }
  ldap_map :preferredLanguage, :preferred_language
  ldap_map :puavoLocale, :locale
  ldap_map :puavoExternalFeed, :external_feed_sources, LdapConverters::ArrayOfJSON
  ldap_map :puavoWlanSSID, :wlan_networks, LdapConverters::ArrayOfJSON
  ldap_map :puavoAllowGuest, :allow_guest, LdapConverters::StringBoolean
  ldap_map :puavoAutomaticImageUpdates, :automatic_image_updates, LdapConverters::StringBoolean
  ldap_map :puavoPersonalDevice, :personal_device, LdapConverters::StringBoolean
  ldap_map(:puavoTag, :tags){ |v| Array(v) }
  ldap_map :gidNumber, :gid_number, LdapConverters::Number
  ldap_map :cn, :abbreviation
  ldap_map(:puavoActiveService, :external_services) do |es|
      Array(es).map { |s| s.downcase.strip }
  end
  ldap_map(:puavoMountpoint, :mountpoints){|m| Array(m).map{|json| JSON.parse(json) }}
  ldap_map :puavoTimezone, :timezone
  ldap_map :puavoKeyboardLayout, :keyboard_layout
  ldap_map :puavoKeyboardVariant, :keyboard_variant
  ldap_map :puavoImageSeriesSourceURL, :image_series_source_urls, LdapConverters::ArrayValue

  ldap_map :puavoDeviceAutoPowerOffMode, :autopoweroff_mode
  ldap_map :puavoDeviceOnHour,           :daytime_start_hour
  ldap_map :puavoDeviceOffHour,          :daytime_end_hour

  before :create do
    if Array(object_classes).empty?
      self.object_classes = ['top','posixGroup','puavoSchool','sambaGroupMapping']
    end

    if id.nil?
      self.id = IdPool.next_id("puavoNextId")
    end

    if gid_number.nil?
      self.gid_number = IdPool.next_id("puavoNextGidNumber")
    end

    if dn.nil?
      self.dn = "puavoId=#{ id },#{ self.class.ldap_base }"
    end

    write_samba_attrs

    # FIXME set sambaSID and sambaGroupType
  end


  def self.ldap_base
    "ou=Groups,#{ organisation["base"] }"
  end

  def self.base_filter
    "(objectClass=puavoSchool)"
  end

  computed_attr :puavo_id
  def puavo_id
    id
  end

  def printer_queues
    @printer_queues ||= PrinterQueue.by_dn_array(printer_queue_dns)
  end

  def wireless_printer_queues
    @wireless_printer_queues ||= PrinterQueue.by_dn_array(wireless_printer_queue_dns)
  end

  def mountpoints=(value)
    write_raw(:puavoMountpoint, value.map{|m| m.to_json})
  end

  # Cached organisation query
  def organisation
    @organisation ||= Organisation.by_dn(self.class.organisation["base"])
  end

  def devices
    Device.by_attr(:school_dn, dn, :multi)
  end

  def ltsp_servers
    LtspServer.by_attr(:school_dns, dn, :multi)
  end

  def preferred_image
    if get_own(:preferred_image)
      return get_own(:preferred_image).strip
    end

    return organisation.preferred_image
  end

  def allow_guest
     if get_own(:allow_guest).nil?
       organisation.allow_guest
     else
       get_own(:allow_guest)
     end
  end

  def automatic_image_updates
     if get_own(:automatic_image_updates).nil?
       organisation.automatic_image_updates
     else
       get_own(:automatic_image_updates)
     end
  end

  def personal_device
     if get_own(:personal_device).nil?
       organisation.personal_device
     else
       get_own(:personal_device)
     end
  end

  def image_series_source_urls
     if get_own(:image_series_source_urls).empty?
       organisation.image_series_source_urls
     else
       get_own(:image_series_source_urls)
     end
  end

  def preferred_language
    if get_own(:preferred_language).nil?
      organisation.preferred_language
    else
      get_own(:preferred_language)
    end
  end

  def locale
    if get_own(:locale).nil?
      organisation.locale
    else
      get_own(:locale)
    end
  end

  def ical_feed_urls
    Array(external_feed_sources).select do |feed|
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
          :source => self.to_hash,
          :error => err.message
        next
      end

      local_store.set("feed:#{ url }", res)
      # Max cache for 12h
      local_store.expire("feed:#{ url }", 60 * 60 * 12)
    end
  end

  def messages
    # TODO: merge with organisation messages

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
    end.compact.flatten.map do |msg|
      msg["to"] = {
        "object_model" => object_model,
        "name" => name,
        "dn" => dn.to_s
      }
      msg
    end
  end

  def timezone
    if get_own(:timezone).nil?
      organisation.timezone
    else
      get_own(:timezone)
    end
  end

  def keyboard_layout
    if get_own(:keyboard_layout).nil?
      organisation.keyboard_layout
    else
      get_own(:keyboard_layout)
    end
  end

  def keyboard_variant
    if get_own(:keyboard_variant).nil?
      organisation.keyboard_variant
    else
      get_own(:keyboard_variant)
    end
  end

  def autopoweroff_attr_with_organisation_fallback(attr)
    [ nil, 'default' ].include?( get_own(:autopoweroff_mode) ) \
      ? organisation.send(attr)                                \
      : get_own(attr)
  end

  autopoweroff_attrs = [ :autopoweroff_mode,
                         :daytime_start_hour,
                         :daytime_end_hour ]
  autopoweroff_attrs.each do |attr|
    define_method(attr) { autopoweroff_attr_with_organisation_fallback(attr) }
  end

  # Write internal samba attributes. Implementation is based on the puavo-web
  # code is not actually tested on production systems
  def write_samba_attrs
    all_samba_domains = SambaDomain.all

    if all_samba_domains.empty?
      raise InternalError, :user => "Cannot find samba domain"
    end

   # Each organisation should have only one
    if all_samba_domains.size > 1
      raise InternalError, :user => "Too many Samba domains"
    end

    samba_domain = all_samba_domains.first

    pool_key = "puavoNextSambaSID:#{ samba_domain.domain }"

    if IdPool.last_id(pool_key).nil?
      IdPool.set_id!(pool_key, samba_domain.legacy_rid)
    end

    rid = IdPool.next_id(pool_key)

    write_raw(:sambaGroupType, ["2"])
    write_raw(:sambaSID, ["#{ samba_domain.sid }-#{ rid - 1}"])

    samba_sid = Array(get_raw(:sambaSID)).first
    if samba_sid && new?
      res = LdapModel.raw_filter(organisation["base"], "(sambaSID=#{ escape samba_sid })")
      if res && !res.empty?
        other_dn = res.first["dn"].first
        # Internal attribute, use underscore prefix to indicate that
        add_validation_error(:__sambaSID, :sambaSID_not_unique, "#{ samba_sid } is already used by #{ other_dn }")
      end
    end
    # Redo validation for samba attrs
    #assert_validation

  end

end

class Schools < PuavoSinatra
  get "/v3/schools" do
    auth :basic_auth, :server_auth, :kerberos
    json School.all
  end

  get "/v3/schools/:school_id/users" do
    auth :basic_auth, :kerberos
    school = School.by_attr!(:id, params["school_id"])
    json User.by_attr(:school_dns, school.dn, :multi)
  end
end



end
