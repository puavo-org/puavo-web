require_relative "../lib/local_store"
require_relative "../lib/samba_attrs"

module PuavoRest
class School < LdapModel
  include LocalStore
  include SambaAttrs

  ldap_map :dn, :dn
  ldap_map :puavoId, :id, LdapConverters::SingleValue
  ldap_map :puavoExternalId, :external_id, LdapConverters::SingleValue
  ldap_map :objectClass, :object_classes, LdapConverters::ArrayValue
  ldap_map :displayName, :name
  ldap_map :puavoSchoolCode, :school_code, LdapConverters::SingleValue
  ldap_map :puavoDeviceImage, :preferred_image
  ldap_map :puavoSchoolHomePageURL, :homepage
  ldap_map(:puavoPrinterQueue, :printer_queue_dns){ |v| Array(v) }
  ldap_map(:puavoWirelessPrinterQueue, :wireless_printer_queue_dns){ |v| Array(v) }
  ldap_map :preferredLanguage, :preferred_language
  ldap_map :puavoLocale, :locale
  ldap_map :puavoWlanSSID, :wlan_networks, LdapConverters::ArrayOfJSON
  ldap_map :puavoAllowGuest, :allow_guest, LdapConverters::StringBoolean
  ldap_map :puavoAutomaticImageUpdates, :automatic_image_updates, LdapConverters::StringBoolean
  ldap_map :puavoPersonalDevice, :personal_device, LdapConverters::StringBoolean
  ldap_map(:puavoTag, :tags){ |v| Array(v) }
  ldap_map :puavoConf, :puavoconf, LdapConverters::PuavoConfObj
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

  # Internal attributes, do not use! These are automatically set when
  # User#school_dns is updated
  ldap_map :member, :member_dns, LdapConverters::ArrayValue
  ldap_map :memberUid, :member_usernames, LdapConverters::ArrayValue

  ldap_map :puavoDeviceAutoPowerOffMode, :autopoweroff_mode
  ldap_map :puavoDeviceOnHour,           :daytime_start_hour
  ldap_map :puavoDeviceOffHour,          :daytime_end_hour

  before :create do
    if Array(object_classes).empty?
      self.object_classes = ['top','posixGroup','puavoSchool','sambaGroupMapping']
    end

    if id.nil?
      self.id = IdPool.next_id("puavoNextId").to_s
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
    Device.by_attr(:school_dn, dn, :multiple => true)
  end

  def ltsp_servers
    LtspServer.by_attr(:school_dns, dn, :multiple => true)
  end

  def preferred_image
    image = get_own(:preferred_image)
    image ? image.strip : organisation.preferred_image
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

  def puavoconf
    (organisation.puavoconf || {}) \
      .merge(get_own(:puavoconf) || {})
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
    set_samba_sid

    write_raw(:sambaGroupType, ["2"])
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
    json User.by_attr(:school_dns, school.dn, :multiple => true)
  end

  get "/v3/schools/:school_id/groups" do
    auth :basic_auth, :kerberos
    school = School.by_attr!(:id, params["school_id"])
    json Group.by_attr(:school_dn, school.dn, :multiple => true)
  end

  get "/v3/schools/:school_id/teaching_groups" do
    auth :basic_auth, :kerberos
    school = School.by_attr!(:id, params["school_id"])
    json Group.teaching_groups_by_school(school)
  end


  # -------------------------------------------------------------------------------------------------
  # -------------------------------------------------------------------------------------------------
  # EXPERIMENTAL V4 API

  # Use at your own risk. Currently read-only.


  # Maps "user" field names to LDAP attributes. Used when searching for data, as only
  # the requested fields are actually returned in the queries.
  USER_TO_LDAP = {
    'allow_guest'           => "puavoAllowGuest",
    'automatic_updates'     => "puavoAutomaticImageUpdates",
    'autopoweroff_mode'     => "puavoDeviceAutoPowerOffMode",
    'autopoweroff_off_hour' => "puavoDeviceOffHour",
    'autopoweroff_on_hour'  => "puavoDeviceOnHour",
    'billing_info'          => "puavoBillingInfo",
    'description'           => "description",
    'dn'                    => 'dn',
    'external_id'           => 'puavoExternalId',
    'fax'                   => "facsimileTelephoneNumber",
    'group_prefix'          => 'cn',
    'homepage'              => "puavoSchoolHomePageURL",
    'id'                    => 'puavoId',
    'image'                 => "puavoDeviceImage",
    'image_series_url'      => "puavoImageSeriesSourceURL",
    'language'              => "preferredLanguage",
    'locale'                => "puavoLocale",
    'location'              => "l",
    'member_dn'             => 'member',
    'member_uid'            => 'memberUid',
    'mount_point'           => "puavoMountpoint",
    'name'                  => 'displayName',
    'name_prefix'           => "puavoNamePrefix",
    'personal_device'       => "puavoPersonalDevice",
    'postal_address'        => "postalAddress",
    'postal_code'           => "postalCode",
    'postal_street'         => "street",
    'post_box'              => "postOfficeBox",
    'puavoconf'             => "puavoConf",
    'school_code'           => 'puavoSchoolCode',
    'state'                 => "st",
    'tags'                  => "puavoTag",
    'telephone'             => "telephoneNumber",
    'wlan_channel'          => "puavoWlanChannel",
    'wlan_ssid'             => "puavoWlanSSID",
  }

  # Maps LDAP attributes back to "user" fields and optionally specifies a conversion type
  LDAP_TO_USER = {
    'cn'                          => { name: 'group_prefix' },
    'description'                 => { name: 'description' },
    'displayName'                 => { name: 'name'},
    'dn'                          => { name: 'dn' },
    'facsimileTelephoneNumber'    => { name: 'fax' },
    'l'                           => { name: 'location' },
    'member'                      => { name: 'member_dn' },
    'memberUid'                   => { name: 'member_uid' },
    'postalAddress'               => { name: 'postal_address' },
    'postalCode'                  => { name: 'postal_code' },
    'postOfficeBox'               => { name: 'post_box' },
    'preferredLanguage'           => { name: 'language' },
    'puavoAllowGuest'             => { name: 'allow_guest', type: :boolean },
    'puavoAutomaticImageUpdates'  => { name: 'automatic_updates', type: :boolean },
    'puavoBillingInfo'            => { name: 'billing_info' },
    'puavoConf'                   => { name: 'puavoconf', type: :json },
    'puavoDeviceAutoPowerOffMode' => { name: 'autopoweroff_mode' },
    'puavoDeviceImage'            => { name: 'image' },
    'puavoDeviceOffHour'          => { name: 'autopoweroff_off_hour', type: :integer },
    'puavoDeviceOnHour'           => { name: 'autopoweroff_on_hour', type: :integer },
    'puavoExternalId'             => { name: 'external_id' },
    'puavoId'                     => { name: 'id', type: :integer },
    'puavoImageSeriesSourceURL'   => { name: 'image_series_url' },
    'puavoLocale'                 => { name: 'locale' },
    'puavoMountpoint'             => { name: 'mount_point', type: :json },
    'puavoNamePrefix'             => { name: 'name_prefix' },
    'puavoPersonalDevice'         => { name: 'personal_device', type: :boolean },
    'puavoSchoolCode'             => { name: 'school_code' },
    'puavoSchoolHomePageURL'      => { name: 'homepage' },
    'puavoTag'                    => { name: 'tags' },
    'puavoWlanChannel'            => { name: 'wlan_channel' },
    'puavoWlanSSID'               => { name: 'wlan_ssid', type: :json },
    'st'                          => { name: 'state' },
    'street'                      => { name: 'postal_street' },
    'telephoneNumber'             => { name: 'telephone' },
  }

  def v4_do_school_search(id, requested_ldap_attrs)
    unless id.class == Array
      raise "do_school_search(): school IDs must be an Array, even if empty"
    end

    filter = v4_build_puavoid_filter('(objectClass=puavoSchool)', id)
    base = "ou=Groups,#{Organisation.current['base']}"

    return School.raw_filter(base, filter, requested_ldap_attrs)
  end

  # Retrieve all (or some) schools in the organisation
  # GET /v4/schools?fields=...
  # GET /v4/schools?id=1,2,3,4,...&fields=...
  get '/v4/schools' do
    auth :basic_auth, :kerberos

    v4_do_operation do
      # which fields to get?
      user_fields = v4_get_fields(params).to_set
      ldap_attrs = v4_user_to_ldap(user_fields, USER_TO_LDAP)

      # zero or more user IDs
      id = v4_get_id_from_params(params)

      # do the query
      raw = v4_do_school_search(id, ldap_attrs)

      # convert and return
      out = v4_ldap_to_user(raw, ldap_attrs, LDAP_TO_USER)
      out = v4_ensure_is_array(out,
        'member_uid', 'member_dns', 'wlan_ssid', 'mountpoint', 'image_series',
        'billing_info')

      return 200, json({
        status: 'ok',
        error: nil,
        data: out,
      })
    end
  end
end
end
