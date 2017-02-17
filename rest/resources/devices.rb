require_relative "./hosts"

module PuavoRest
class Device < Host
  ldap_map :puavoAllowGuest,               :allow_guest,              LdapConverters::StringBoolean
  ldap_map :puavoAutomaticImageUpdates,    :automatic_image_updates,  LdapConverters::StringBoolean
  ldap_map :puavoDefaultPrinter,           :default_printer_name
  ldap_map :puavoDeviceAutoPowerOffMode,   :autopoweroff_mode
  ldap_map :puavoDeviceDefaultAudioSink,   :default_audio_sink
  ldap_map :puavoDeviceDefaultAudioSource, :default_audio_source
  ldap_map :puavoDeviceKernelArguments,    :kernel_arguments
  ldap_map :puavoDeviceKernelVersion,      :kernel_version
  ldap_map :puavoDeviceModel,              :model
  ldap_map :puavoDeviceOffHour,            :daytime_end_hour
  ldap_map :puavoDeviceOnHour,             :daytime_start_hour
  ldap_map :puavoDevicePrimaryUser,        :primary_user_dn
  ldap_map :puavoDeviceResolution,         :resolution
  ldap_map :puavoDeviceVertRefresh,        :vertical_refresh
  ldap_map :puavoDeviceXrandrDisable,      :xrandr_disable,           LdapConverters::StringBoolean
  ldap_map :puavoDeviceXrandr,             :xrandr,                   LdapConverters::ArrayValue
  ldap_map :puavoDeviceXserver,            :graphics_driver
  ldap_map :puavoImageSeriesSourceURL,     :image_series_source_urls, LdapConverters::ArrayValue
  ldap_map :puavoKeyboardLayout,           :keyboard_layout
  ldap_map :puavoKeyboardVariant,          :keyboard_variant
  ldap_map :puavoMountpoint,               :mountpoints,              LdapConverters::ArrayValue
  ldap_map :puavoPersonalDevice,           :personal_device,          LdapConverters::StringBoolean
  ldap_map :puavoPersonallyAdministered,   :personally_administered,  LdapConverters::StringBoolean
  ldap_map :puavoPreferredServer,          :preferred_server
  ldap_map :puavoPrinterDeviceURI,         :printer_device_uri
  ldap_map :puavoPrinterQueue,             :printer_queue_dns,        LdapConverters::ArrayValue
  ldap_map :puavoSchool,                   :school_dn
  ldap_map :puavoTimezone,                 :timezone

  def self.ldap_base
    "ou=Devices,ou=Hosts,#{ organisation["base"] }"
  end


  def self.by_hostname(hostname)
    by_attr(:hostname, hostname)
  end

  def self.by_hostname!(hostname)
    by_attr!(:hostname, hostname)
  end

  # Find device by it's mac address
  def self.by_mac_address!(mac_address)
    by_attr!(:hostname, mac_address)
  end

  def printer_ppd
    Array(self.class.raw_by_dn(dn, :ldap_attrs => ["puavoPrinterPPD"])["puavoPrinterPPD"]).first
  end

  # Cached school query
  def school
    @school ||= School.by_dn(school_dn)
  end

  def printer_queues
    @printer_queues ||= PrinterQueue.by_dn_array(printer_queue_dns)
  end

  computed_attr :preferred_language
  def preferred_language
    school.preferred_language
  end

  computed_attr :locale
  def locale
    school.locale
  end

  computed_attr :primary_user
  def primary_user
    if user_dn = get_own(:primary_user_dn)
      begin
        return User.by_dn!(user_dn, :attrs => ["username"]).username
      rescue NotFound
        return ""
      end
    end
  end

  def primary_user=(username)
    if username.nil?
      self.primary_user_dn = nil
      return
    end

    user = User.by_username!(username, :attrs => ["username"])
    self.primary_user_dn = user.dn
    username
  end

  def preferred_image
     image = get_own(:preferred_image)

     # Always fallback to school's preferred image
     image ||= school.get_own(:preferred_image)

     # Bootserver's preferred image is used only for netboot devices
     # so that localboot devices get always consistent settings
     if !image and netboot?
       image = BootServer.current_image
     end

     # Organisation fallback
     image ||= school.organisation.preferred_image

     image.strip if image
  end

  def allow_guest
     if get_own(:allow_guest).nil?
        school.allow_guest
      else
        get_own(:allow_guest)
      end
  end

  def automatic_image_updates
     if get_own(:automatic_image_updates).nil?
        school.automatic_image_updates
      else
        get_own(:automatic_image_updates)
      end
  end

  def personal_device
     if get_own(:personal_device).nil?
       school.personal_device
     else
       get_own(:personal_device)
     end
  end

  def image_series_source_urls
    if get_own(:image_series_source_urls).empty?
      school.image_series_source_urls
    else
      get_own(:image_series_source_urls)
    end
  end

  def tags
    school.tags.concat(get_own(:tags)).uniq.sort
  end

  computed_attr :homepage
  def homepage
    school.homepage
  end

  def messages
    # TODO: merge with devices own messages
    school.messages
  end

  # Merge device's and school's mountpoints.
  # Use device's mountpoint if it is same that at school
  def mountpoints
    device_mounts = get_own(:mountpoints).map{ |m| JSON.parse(m) }
    school_mounts = school.mountpoints
    mountpoints = device_mounts.map{ |m| m["mountpoint"] }

    school_mounts.each do |mounts|
      next if mountpoints.include?(mounts["mountpoint"])

      device_mounts.push(mounts)
    end
    device_mounts
  end

  def self.search_filters
    [
      create_filter_lambda(:hostname) { |v| "*#{ v }*" },

      # Our ldap schema does not allow wildcards in the 'macAddress' field. So
      # we must match only with excact filters
      create_filter_lambda(:mac_address) { |v| v },
    ]
  end

  def timezone
    if get_own(:timezone).nil?
      school.timezone
    else
      get_own(:timezone)
    end
  end

  def keyboard_layout
    if get_own(:keyboard_layout).nil?
      school.keyboard_layout
    else
      get_own(:keyboard_layout)
    end
  end

  def keyboard_variant
    if get_own(:keyboard_variant).nil?
      school.keyboard_variant
    else
      get_own(:keyboard_variant)
    end
  end

  def autopoweroff_attr_with_school_fallback(attr)
    [ nil, 'default' ].include?( get_own(:autopoweroff_mode) ) \
      ? school.send(attr)                                      \
      : get_own(attr)
  end

  autopoweroff_attrs = [ :autopoweroff_mode,
                         :daytime_start_hour,
                         :daytime_end_hour ]
  autopoweroff_attrs.each do |attr|
    define_method(attr) { autopoweroff_attr_with_school_fallback(attr) }
  end

  def puavo_conf
    conf = {}

    update = lambda do |key, value, fn=nil|
	       return if value.nil?
	       newvalue = fn ? fn.call(value) : value
	       return if newvalue.nil?
	       conf[key] = newvalue.to_s
	     end

    default_means_nothing = lambda { |v| v == 'default' ? nil : v }
    no_empty_string = lambda { |v| (v.kind_of?(String) && v.empty?) ? nil : v }
    to_json = lambda { |v| v.to_json }

    update.call('puavo.admin.personally_administered', personally_administered)
    update.call('puavo.admin.primary_user', primary_user, no_empty_string)
    update.call('puavo.audio.pa.default_sink', default_audio_sink)
    update.call('puavo.audio.pa.default_source', default_audio_source)
    update.call('puavo.autopoweroff.enabled',
		autopoweroff_mode,
		default_means_nothing)
    update.call('puavo.autopoweroff.daytime_start_hour', daytime_start_hour)
    update.call('puavo.autopoweroff.daytime_end_hour',   daytime_end_hour)
    update.call('puavo.guestlogin.enabled',              allow_guest)
    update.call('puavo.homepage',                        homepage)
    update.call('puavo.hostname',                        hostname)
    update.call('puavo.image.automatic_updates',
		automatic_image_updates)
    update.call('puavo.image.preferred', preferred_image)
    update.call('puavo.image.series.urls',
		image_series_source_urls,
		to_json)
    update.call('puavo.kernel.arguments',         kernel_arguments)
    update.call('puavo.kernel.version',           kernel_version)
    update.call('puavo.keyboard_layout',          keyboard_layout)
    update.call('puavo.keyboard_variant',         keyboard_variant)
    update.call('puavo.l10n.locale',		  locale)
    update.call('puavo.mounts.extramounts',	  mountpoints)
    update.call('puavo.printing.default_printer', default_printer_name)
    update.call('puavo.printing.device_uri',      printer_device_uri)
    update.call('puavo.timezone',                 timezone)
    update.call('puavo.xorg.server',              graphics_driver)
    update.call('puavo.xrandr_disable',           xrandr_disable)
    update.call('puavo.xrandr',                   xrandr, to_json)

    taghash = Hash[ tags.map { |k| [ k, 1 ] } ]

    tagswitch = lambda do |puavo_conf_key, truetag, falsetag|
      # falsetag is stronger than truetag
      flag = taghash.has_key?(truetag) && !taghash.has_key?(falsetag) \
               ? 'true'  \
               : 'false'
      update.call(puavo_conf_key, flag)
    end

    taghash.keys.each do |tag|
      case tag
        when 'autopoweron', 'no_autopoweron'
          tagswitch.call('puavo.autopoweron.enabled',
			 'autopoweron',
			 'no_autopoweron')
        when /\Aautopilot:?(.*)\z/
	  mode, username, password = * $1.split(':')
          update.call('puavo.autopilot.enabled',  'true')
          update.call('puavo.autopilot.mode',     mode)     if mode
          update.call('puavo.autopilot.username', username) if username
          update.call('puavo.autopilot.password', password) if password
        when 'blacklist_bcmwl', 'no_blacklist_bcmwl'
	  if taghash.has_key?('blacklist_bcmwl') \
	    && !taghash.has_key?('no_blacklist_bcmwl') then
              update.call('puavo.kernel.modules.blacklist', 'wl')
	  end
        when /\Adconf_scaling_factor:(.*)\z/
          update.call('puavo.desktop.dconf.settings',
	    "/org/gnome/desktop/interface/scaling-factor=uint32 #{ $1 }")
        when /\Adefault_xsession:(.*)\z/
          update.call('puavo.xsessions.default', $1)
        when /\Adesktop_background:(.*)\z/
          update.call('puavo.desktop.background', $1)
        when 'disable-acpi-wakeup'
          tagswitch.call('puavo.acpi.wakeup.enabled',
			 'no-disable-acpi-wakeup',
			 'disable-acpi-wakeup')
        when 'enable_all_xsessions'
          update.call('puavo.xsessions.locked', 'false')
        when 'enable_webmenu_feedback'
          update.call('puavo.webmenu.feedback.enabled', 'true')
        when 'force_puavo_xrandr'
          tagswitch.call('puavo.xrandr.forced',
			 'force_puavo_xrandr',
			 'no_force_puavo_xrandr')
      end
    end

    return conf
  end
end

class Devices < PuavoSinatra

  get "/v3/devices/_search" do
    auth :basic_auth, :kerberos
    json Device.search(params["q"])
  end

  # Get detailed information about the server by hostname
  #
  # Example:
  #
  #    GET /v3/devices/testthin
  #
  #    {
  #      "kernel_arguments": "lol",
  #      "kernel_version": "0.1",
  #      "vertical_refresh": "2",
  #      "resolution": "320x240",
  #      "graphics_driver": "nvidia",
  #      "image": "myimage",
  #      "dn": "puavoId=10,ou=Devices,ou=Hosts,dc=edu,dc=hogwarts,dc=fi",
  #      "puavo_id": "10",
  #      "mac_address": "08:00:27:88:0c:a6",
  #      "type": "thinclient",
  #      "school": "puavoId=1,ou=Groups,dc=edu,dc=hogwarts,dc=fi",
  #      "hostname": "testthin",
  #      "boot_mode": "netboot",
  #      "xrand_disable": "FALSE"
  #    }
  #
  #
  # @!macro route
  get "/v3/devices/:hostname" do
    auth :basic_auth, :server_auth, :legacy_server_auth

    device_object = Device.by_hostname!(params["hostname"])
    device = device_object.to_hash

    device['conf'] = device_object.puavo_conf

    json device
  end

  # get "/v3/devices/:hostname" do
  #   auth :basic_auth, :server_auth, :legacy_server_auth

  #   device = Device.by_hostname!(params["hostname"])
  #   json device
  # end

  post "/v3/devices/:hostname" do
    auth :basic_auth, :kerberos
    device = Device.by_hostname!(params["hostname"])
    device.update!(json_params)
    device.save!
    json device
  end



  get "/v3/devices" do
    auth :basic_auth, :server_auth, :kerberos
    json Device.all(:attrs => attribute_list)
  end

  get "/v3/devices/:hostname/feed" do

    messages = LdapModel.setup(:credentials => CONFIG["server"]) do
      Device.by_hostname!(params["hostname"]).messages
    end

    json messages
  end


  get "/v3/devices/:hostname/wireless_printer_queues" do
    auth :basic_auth, :server_auth

    device = Device.by_hostname!(params["hostname"])
    json device.school.wireless_printer_queues
  end

end
end
