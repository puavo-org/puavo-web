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

  def generate_device_puavo_conf
    conf = {}

    update = lambda do |key, value, fn=nil|
	       return if value.nil?
	       newvalue = fn ? fn.call(value) : value
	       return if newvalue.nil?
	       conf[key] = newvalue.to_s
	     end

    no_empty_string = lambda { |v| (v.kind_of?(String) && v.empty?) ? nil : v }
    to_json = lambda { |v| v.to_json }

    handle_xrandr = lambda do |source_xrandr_strings_array|
      target_xrandr_strings_array = []
      source_xrandr_strings_array.each do |xrandr_string|
        # support the old command="..." syntax
        if xrandr_string.match(/^\s*command="(xrandr\s+|)(.*)"\s*$/) then
          target_xrandr_strings_array << $2
        else
          target_xrandr_strings_array << xrandr_string
        end
      end

      target_xrandr_strings_array.to_json
    end

    update.call('puavo.admin.personally_administered', personally_administered)
    update.call('puavo.admin.primary_user', primary_user, no_empty_string)
    update.call('puavo.audio.pa.default_sink', default_audio_sink)
    update.call('puavo.audio.pa.default_source', default_audio_source)

    case autopoweroff_mode
      when 'custom'
        update.call('puavo.autopoweroff.enabled', 'true')
      when 'off'
        update.call('puavo.autopoweroff.enabled', 'false')
    end

    update.call('puavo.autopoweroff.daytime_start_hour', daytime_start_hour)
    update.call('puavo.autopoweroff.daytime_end_hour',   daytime_end_hour)
    update.call('puavo.desktop.keyboard.layout',         keyboard_layout)
    update.call('puavo.desktop.keyboard.variant',        keyboard_variant)
    update.call('puavo.guestlogin.enabled',              allow_guest)
    update.call('puavo.image.automatic_updates',
		automatic_image_updates)
    update.call('puavo.image.preferred', preferred_image)
    update.call('puavo.image.series.urls',
		image_series_source_urls,
		to_json)
    update.call('puavo.kernel.arguments',         kernel_arguments)
    update.call('puavo.kernel.version',           kernel_version)
    update.call('puavo.l10n.locale',		  locale)
    update.call('puavo.mounts.extramounts',	  mountpoints, to_json)
    update.call('puavo.printing.default_printer', default_printer_name)
    update.call('puavo.printing.device_uri',      printer_device_uri)

    profiles = [ self.type,
                 (tags.include?('bigtouch') ? 'bigtouch' : nil),
                 (tags.include?('infotv')   ? 'infotv'   : nil),
                 (tags.include?('webkiosk') ? 'webkiosk' : nil),
                 (personally_administered   ? 'personal' : nil),
               ]
    update.call('puavo.profiles.list', profiles.compact.join(','))

    update.call('puavo.time.timezone',            timezone)
    update.call('puavo.www.homepage',             homepage)
    update.call('puavo.xorg.server',              graphics_driver)

    if xrandr_disable then
      update.call('puavo.xrandr.args', '[]')
    else
      update.call('puavo.xrandr.args', xrandr, handle_xrandr)
    end

    #
    # handle tags by mapping tags to puavo-conf
    #

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
	when 'disable-acpi-wakeup', 'no-disable-acpi-wakeup'
	  tagswitch.call('puavo.acpi.wakeup.enabled',
			 'no-disable-acpi-wakeup',
			 'disable-acpi-wakeup')
	when 'enable_all_xsessions', 'disable_all_xsessions'
	  tagswitch.call('puavo.xsessions.locked',
			 'disable_all_xsessions',
			 'enable_all_xsessions')
	when 'enable_webmenu_feedback', 'disable_webmenu_feedback'
	  tagswitch.call('puavo.webmenu.feedback.enabled',
			 'enable_webmenu_feedback',
			 'disable_webmenu_feedback')
	when 'force_puavo_xrandr'
	  tagswitch.call('puavo.xrandr.forced',
			 'force_puavo_xrandr',
			 'no_force_puavo_xrandr')
	when /\Agreeter_background:(.*)\z/
	  update.call('puavo.greeter.background.default', $1)
	when /\Agreeter_background_firstlogin:(.*)\z/
	  update.call('puavo.greeter.background.firstlogin', $1)
	when /\Agreeter_background_mode:(.*)\z/
	  update.call('puavo.greeter.background.mode', $1)
	when /\Agreeter_background_random_subdir:(.*)\z/
	  update.call('puavo.greeter.background.random.subdir', $1)
	when /\Ahitachicalib:(.*)\z/
	  hitachi_calibration = $1.split(':').join(' ')
	  update.call('puavo.xorg.inputs.hitachi.calibration',
		      hitachi_calibration)
	when /\Aimagedownload-rate-limit:(.*)\z/
	  update.call('puavo.image.download.ratelimit', $1)
	when 'intel-backlight', 'no-intel-backlight'
	  tagswitch.call('puavo.xorg.intel_backlight',
			 'intel-backlight',
			 'no-intel-backlight')
	when 'jetpipe', 'no_jetpipe'
	  tagswitch.call('puavo.printing.jetpipe.enabled',
			 'jetpipe',
			 'no_jetpipe')
	when /\Akeep_system_service:(.*)\z/
	  update.call("puavo.service.#{ $1 }.enabled", 'true')
	when /\Arm_system_service:(.*)\z/
	  update.call("puavo.service.#{ $1 }.enabled", 'false')
	when 'noaccel', 'no_noaccel'
	  tagswitch.call('puavo.xorg.noaccel', 'noaccel', 'no_noaccel')
	when 'nokeyboard', 'no_nokeyboard'
	  tagswitch.call('puavo.onscreenkeyboard.enabled',
			 'nokeyboard',
			 'no_nokeyboard')
	when 'nolidsuspend', 'no_nolidsuspend'
	  tagswitch.call('puavo.pm.lidsuspend.enabled',
			 'no_nolidsuspend',
			 'nolidsuspend')
	when 'noremoteassistanceapplet', 'no_noremoteassistanceapplet'
	  tagswitch.call('puavo.support.applet.enabled',
			 'no_noremoteassistanceapplet',
			 'noremoteassistanceapplet')
	when 'nosuspend', 'no_nosuspend'
	  tagswitch.call('puavo.pm.suspend.enabled',
			 'no_nosuspend',
			 'nosuspend')
	when 'no-wifi-powersave', 'no-no-wifi-powersave'
	  tagswitch.call('puavo.pm.wireless.enabled',
			 'no-no-wifi-powersave',
			 'no-wifi-powersave')
	when /\Arm_session_service:(.*)\z/
	  update.call("puavo.desktop.service.#{ $1 }.enabled", 'false')
	when 'smartboard', 'no_smartboard'
	  tagswitch.call('puavo.nonfree.smartboard.enabled',
			 'smartboard',
			 'no_smartboard')
	when 'use_puavo_printer_permissions'
	  update.call('puavo.printing.use_puavo_permissions', 'true')
	when 'use_remotemounts', 'no_use_remotemounts'
	  tagswitch.call('puavo.mounts.by_user_from_bootserver.enabled',
			 'use_remotemounts',
			 'no_use_remotemounts')
	when /\Awlanap_channels:(.*)\z/
	  update.call('puavo.wireless.ap.channels', $1)
	when /\Awlanap_reconf_interval:(.*)\z/
	  update.call('puavo.wireless.ap.reconf_interval', $1)
	when /\Awlanap_report_interval:(.*)\z/
	  update.call('puavo.wireless.ap.report_interval', $1)
	when /\Awlanap_rssi_kick_interval:(.*)\z/
	  update.call('puavo.wireless.ap.rssi_kick.interval', $1)
	when /\Awlanap_rssi_kick_threshold:(.*)\z/
	  update.call('puavo.wireless.ap.rssi_kick.threshold', $1)
	when /\Awlanap_tx_power:(.*)\z/
	  update.call('puavo.wireless.ap.tx.power', $1)
	when /\Awlanap_tx_power_2g:(.*)\z/
	  update.call('puavo.wireless.ap.tx.power.2g', $1)
	when /\Awlanap_tx_power_5g:(.*)\z/
	  update.call('puavo.wireless.ap.tx.power.5g', $1)
	when /\Axbacklight:(.*)\z/
	  update.call('puavo.xorg.backlight.brightness', $1)
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

    device['conf'] = device_object.generate_device_puavo_conf

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
