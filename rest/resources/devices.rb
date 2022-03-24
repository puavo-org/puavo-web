require_relative "./hosts"
require_relative '../lib/inventory.rb'

module PuavoRest
class Device < Host
  ldap_map :puavoAllowGuest,               :allow_guest,              LdapConverters::StringBoolean
  ldap_map :puavoDefaultPrinter,           :default_printer_name
  ldap_map :puavoDeviceAutoPowerOffMode,   :autopoweroff_mode
  ldap_map :puavoDeviceDefaultAudioSink,   :default_audio_sink
  ldap_map :puavoDeviceDefaultAudioSource, :default_audio_source
  ldap_map :puavoDeviceModel,              :model
  ldap_map :puavoDeviceMonitorsXML,        :monitors_xml
  ldap_map :puavoDeviceOffHour,            :daytime_end_hour
  ldap_map :puavoDeviceOnHour,             :daytime_start_hour
  ldap_map :puavoDevicePrimaryUser,        :primary_user_dn
  ldap_map :puavoDeviceXrandr,             :xrandr,                   LdapConverters::ArrayValue
  ldap_map :puavoDeviceXserver,            :graphics_driver
  ldap_map :puavoMountpoint,               :mountpoints,              LdapConverters::ArrayValue
  ldap_map :puavoPersonalDevice,           :personal_device,          LdapConverters::StringBoolean
  ldap_map :puavoPersonallyAdministered,   :personally_administered,  LdapConverters::StringBoolean
  ldap_map :puavoPrinterDeviceURI,         :printer_device_uri
  ldap_map :puavoPrinterQueue,             :printer_queue_dns,        LdapConverters::ArrayValue
  ldap_map :puavoSchool,                   :school_dn

  def self.ldap_base
    "ou=Devices,ou=Hosts,#{ organisation["base"] }"
  end


  def self.by_hostname(hostname)
    by_attr(:hostname, hostname)
  end

  def self.by_hostname!(hostname)
    by_attr!(:hostname, hostname)
  end

  # Like by_hostname, but returns the low-level raw data and only the attributes you ask.
  # (The "raw_by_dn" method wants a DN, and I have a hostname.)
  def self.by_hostname_raw_attrs(hostname, attributes)
    self.raw_filter(self.ldap_base(), "(&(objectclass=*)(puavoHostname=#{LdapModel.ldap_escape(hostname)}))", attributes)
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

  # XXX deprecated, not needed by recent clients and may be removed
  # XXX sometime in the future
  def printer_queues
    @printer_queues ||= PrinterQueue.by_dn_array(printer_queue_dns)
  end

  computed_attr :preferred_language
  def preferred_language
    school.preferred_language
  end

  computed_attr :printers
  def printers
    restrictions = {}

    PrinterQueue.all.each do |pq|
      if school.wireless_printer_queue_dns.include?(pq.dn) then
        restrictions[pq.name] = {
          :allow     => '*',
          :rationale => 'OPENINTHISSCHOOL',
        }
        next
      end

      printer_schools = School.by_attr(:wireless_printer_queue_dns,
                                       pq.dn,
                                       :multiple => true)
      if !printer_schools.empty? then
        restrictions[pq.name] = {
          :allow     => '*',
          :rationale => 'OPENINSOMESCHOOL',
        }
        next
      end

      if school.printer_queue_dns.include?(pq.dn) then
        restrictions[pq.name] = {
          :allow     => '*',
          :rationale => 'PRINTERINSAMESCHOOL',
        }
        next
      end

      if printer_queue_dns.include?(pq.dn) then
        restrictions[pq.name] = {
          :allow     => '*',
          :rationale => 'DEVICESPECIFIC',
        }
        next
      end

      groups = Group.by_attr(:printer_queue_dns, pq.dn, :multiple => true)
      if !groups.empty? then
        restrictions[pq.name] = {
          :allow     => groups.map { |g| "@#{ g.abbreviation }" }.join(','),
          :rationale => 'GROUPSPECIFIC',
        }
        next
      end

      restrictions[pq.name] = {
        :deny      => '*',
        :rationale => 'NOPERMISSION',
      }
    end

    { :restrictions => restrictions }
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

     # Bootserver's preferred boot image is used only for netboot devices
     # so that localboot devices get always consistent settings.
     if !image and netboot? then
       image = BootServer.on_bootserver_preferred_boot_image
     end

     # Organisation fallback
     image ||= school.organisation.preferred_image

     # Bootserver's preferred image is used only for netboot devices
     # so that localboot devices get always consistent settings.
     if !image and netboot? then
       image = BootServer.on_bootserver_preferred_image
     end

     image ? image.strip : nil
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

  def puavoconf
    (school.puavoconf || {}) \
      .merge(get_own(:puavoconf) || {})
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
      # we must match only with exact filters
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

  def generate_extended_puavo_conf
    # creates/updates @extended_puavoconf
    super

    no_empty_string = lambda { |v| (v.kind_of?(String) && v.empty?) ? nil : v }

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

    extend_puavoconf('puavo.admin.personally_administered',
                     personally_administered)
    extend_puavoconf('puavo.admin.primary_user', primary_user, no_empty_string)
    extend_puavoconf('puavo.audio.pa.default_sink', default_audio_sink)
    extend_puavoconf('puavo.audio.pa.default_source', default_audio_source)

    case autopoweroff_mode
      when 'custom'
        extend_puavoconf('puavo.autopoweroff.enabled', 'true')
      when 'off'
        extend_puavoconf('puavo.autopoweroff.enabled', 'false')
    end

    extend_puavoconf('puavo.autopoweroff.daytime_start_hour',
                     daytime_start_hour)
    extend_puavoconf('puavo.autopoweroff.daytime_end_hour',
                     daytime_end_hour)
    extend_puavoconf('puavo.guestlogin.enabled', allow_guest)
    extend_puavoconf('puavo.l10n.locale', locale)
    extend_puavoconf('puavo.mounts.extramounts',
                     mountpoints,
                     lambda { |v| v.to_json })
    extend_puavoconf('puavo.printing.default_printer', default_printer_name)
    extend_puavoconf('puavo.printing.device_uri', printer_device_uri)
    extend_puavoconf('puavo.www.homepage',  homepage)
    extend_puavoconf('puavo.xorg.server',   graphics_driver)
    extend_puavoconf('puavo.xrandr.args', xrandr, handle_xrandr)

    #
    # handle tags by mapping tags to puavo-conf
    #

    taghash = Hash[ tags.map { |k| [ k, 1 ] } ]

    tagswitch = lambda do |puavo_conf_key, truetag, falsetag|
      # falsetag is stronger than truetag
      flag = taghash.has_key?(truetag) && !taghash.has_key?(falsetag) \
               ? 'true'  \
               : 'false'
      extend_puavoconf(puavo_conf_key, flag)
    end

    taghash.keys.each do |tag|
      case tag
        when 'autopoweron', 'no_autopoweron'
          tagswitch.call('puavo.autopoweron.enabled',
                         'autopoweron',
                         'no_autopoweron')
        when /\Aautopilot:?(.*)\z/
          mode, username, password = * $1.split(':')
          extend_puavoconf('puavo.autopilot.enabled',  'true')
          extend_puavoconf('puavo.autopilot.mode',     mode)     if mode
          extend_puavoconf('puavo.autopilot.username', username) if username
          extend_puavoconf('puavo.autopilot.password', password) if password
        when 'blacklist_bcmwl', 'no_blacklist_bcmwl'
          if taghash.has_key?('blacklist_bcmwl') \
            && !taghash.has_key?('no_blacklist_bcmwl') then
              extend_puavoconf('puavo.kernel.modules.blacklist', 'wl')
          end
        when /\Adconf_scaling_factor:(.*)\z/
          extend_puavoconf('puavo.desktop.dconf.settings',
            "/org/gnome/desktop/interface/scaling-factor=uint32 #{ $1 }")
        when /\Adefault_xsession:(.*)\z/
          extend_puavoconf('puavo.xsessions.default', $1)
        when /\Adesktop_background:(.*)\z/
          extend_puavoconf('puavo.desktop.background', $1)
        when 'disable-acpi-wakeup', 'no-disable-acpi-wakeup'
          tagswitch.call('puavo.acpi.wakeup.enabled',
                         'no-disable-acpi-wakeup',
                         'disable-acpi-wakeup')
        when 'enable_all_xsessions', 'disable_all_xsessions'
          tagswitch.call('puavo.xsessions.locked',
                         'disable_all_xsessions',
                         'enable_all_xsessions')
        when 'force_puavo_xrandr'
          tagswitch.call('puavo.xrandr.forced',
                         'force_puavo_xrandr',
                         'no_force_puavo_xrandr')
        when /\Agreeter_background:(.*)\z/
          extend_puavoconf('puavo.greeter.background.default', $1)
        when /\Agreeter_background_firstlogin:(.*)\z/
          extend_puavoconf('puavo.greeter.background.firstlogin', $1)
        when /\Agreeter_background_mode:(.*)\z/
          extend_puavoconf('puavo.greeter.background.mode', $1)
        when /\Agreeter_background_random_subdir:(.*)\z/
          extend_puavoconf('puavo.greeter.background.random.subdir', $1)
        when /\Ahitachicalib:(.*)\z/
          hitachi_calibration = $1.split(':').join(' ')
          extend_puavoconf('puavo.xorg.inputs.hitachi.calibration',
                           hitachi_calibration)
        when /\Aimagedownload-rate-limit:(.*)\z/
          extend_puavoconf('puavo.image.download.ratelimit', $1)
        when 'intel-backlight', 'no-intel-backlight'
          tagswitch.call('puavo.xorg.intel_backlight',
                         'intel-backlight',
                         'no-intel-backlight')
        when 'jetpipe', 'no_jetpipe'
          tagswitch.call('puavo.printing.jetpipe.enabled',
                         'jetpipe',
                         'no_jetpipe')
        when /\Akeep_system_service:(.*)\z/
          extend_puavoconf("puavo.service.#{ $1 }.enabled", 'true')
        when /\Arm_system_service:(.*)\z/
          extend_puavoconf("puavo.service.#{ $1 }.enabled", 'false')
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
          extend_puavoconf("puavo.desktop.service.#{ $1 }.enabled", 'false')
        when 'smartboard', 'no_smartboard'
          tagswitch.call('puavo.nonfree.smartboard.enabled',
                         'smartboard',
                         'no_smartboard')
        when 'ti_nspire_cx_cas', 'no_ti_nspire_cx_cas'
          tagswitch.call('puavo.nonfree.ti_nspire_cx_cas_ss.enabled',
                         'ti_nspire_cx_cas',
                         'no_ti_nspire_cx_cas')
        when 'use_puavo_printer_permissions'
          extend_puavoconf('puavo.printing.use_puavo_permissions', 'true')
        when 'use_remotemounts', 'no_use_remotemounts'
          tagswitch.call('puavo.mounts.by_user_from_bootserver.enabled',
                         'use_remotemounts',
                         'no_use_remotemounts')
        when /\Awlanap_channels:(.*)\z/
          extend_puavoconf('puavo.wireless.ap.channels', $1)
        when /\Awlanap_reconf_interval:(.*)\z/
          extend_puavoconf('puavo.wireless.ap.reconf_interval', $1)
        when /\Awlanap_report_interval:(.*)\z/
          extend_puavoconf('puavo.wireless.ap.report_interval', $1)
        when /\Awlanap_rssi_kick_interval:(.*)\z/
          extend_puavoconf('puavo.wireless.ap.rssi_kick.interval', $1)
        when /\Awlanap_rssi_kick_threshold:(.*)\z/
          extend_puavoconf('puavo.wireless.ap.rssi_kick.threshold', $1)
        when /\Awlanap_tx_power:(.*)\z/
          extend_puavoconf('puavo.wireless.ap.tx.power', $1)
        when /\Awlanap_tx_power_2g:(.*)\z/
          extend_puavoconf('puavo.wireless.ap.tx.power.2g', $1)
        when /\Awlanap_tx_power_5g:(.*)\z/
          extend_puavoconf('puavo.wireless.ap.tx.power.5g', $1)
        when /\Axbacklight:(.*)\z/
          extend_puavoconf('puavo.xorg.backlight.brightness', $1)
      end
    end

    return @extended_puavoconf
  end
end

class Devices < PuavoSinatra
  def auth_connect_to_ldapmaster(*authlist)
    if CONFIG['bootserver'] then
      if !CONFIG['ldapmaster'] then
        raise InternalError,
              :user => 'Cannot connect to ldapmaster because it is not known'
      end
      LdapModel.disconnect()
      auth *authlist
      LdapModel.setup(:credentials => CONFIG['server'],
                      :ldap_server => CONFIG['ldapmaster'])
    else
      auth *authlist
    end
  end

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
  #      "graphics_driver": "nvidia",
  #      "image": "myimage",
  #      "dn": "puavoId=10,ou=Devices,ou=Hosts,dc=edu,dc=hogwarts,dc=net",
  #      "puavo_id": "10",
  #      "mac_address": "08:00:27:88:0c:a6",
  #      "type": "thinclient",
  #      "school": "puavoId=1,ou=Groups,dc=edu,dc=hogwarts,dc=net",
  #      "hostname": "testthin",
  #      "boot_mode": "netboot",
  #      "xrand_disable": "FALSE"
  #    }
  #
  #
  # @!macro route
  get "/v3/devices/:hostname" do
    auth :basic_auth, :server_auth, :legacy_server_auth

    json Device.create_device_info(params['hostname'])
  end

  # get "/v3/devices/:hostname" do
  #   auth :basic_auth, :server_auth, :legacy_server_auth

  #   device = Device.by_hostname!(params["hostname"])
  #   json device
  # end

  # Monitors configuration receiver
  post '/v3/devices/:hostname/monitors' do
    auth_connect_to_ldapmaster :basic_auth, :server_auth, :legacy_server_auth

    device = Device.by_hostname!(params['hostname'])

    raise BadInput, :user => 'no monitors.xml provided as a parameter' \
      unless json_params.has_key?('monitors.xml')
    raise BadInput, :user => 'monitors.xml is not a string' \
      unless json_params['monitors.xml'].kind_of?(String)

    device.monitors_xml = json_params['monitors.xml']
    device.save!
  end

  # Hardware info receiver
  post '/v3/devices/:hostname/sysinfo' do
    auth_connect_to_ldapmaster :basic_auth, :server_auth, :legacy_server_auth

    begin
      device = Device.by_hostname!(params["hostname"])
      device.save_hwinfo!(params[:sysinfo])

      rlog.info("received sysinfo from device '#{params['hostname']}'")

      if CONFIG['inventory_management']
        # Notify the external inventory management
        Puavo::Inventory::send_device_hardware_info(rlog, CONFIG['inventory_management'], device, params[:sysinfo])
      end

      json({ :status => 'successfully' })
    rescue NotFound => e
      status 404
      rlog.error("sysinfo receiving failed, could not find device by hostname '#{params["hostname"]}'")
      json({ :status => 'failed',
             :error  => 'could not find device by hostname' })
    rescue StandardError => e
      status 404
      rlog.error("sysinfo receiving failed for device '#{params['hostname']}': #{e.message}")
      json({ :status => 'failed', :error => 'failed due to unknown error' })
    end
  end

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

  get "/v3/devices/:hostname/wireless_printer_queues" do
    auth :basic_auth, :server_auth

    device = Device.by_hostname!(params["hostname"])
    json device.school.wireless_printer_queues
  end

  # List all Abitti exam servers in the current organisation. School-level
  # filtering must be done on the client-side.
  get "/v3/abitti_exam_servers" do
    auth :basic_auth, :server_auth

    # Get all laptop devices that have a non-empty puavoconf string. Only
    # return the attributes we want.
    base = Organisation.current['base']

    potential_devices = Device.raw_filter(
      "ou=Devices,ou=Hosts,#{base}",
      '(&(objectclass=*)(&(puavoDeviceType=laptop)(puavoConf=*)))',
      ['puavoId', 'puavoHostname', 'puavoSchool', 'puavoConf']
    )

    # Do further filtering. Our LDAP schema does not make "puavoConf"
    # substring-searchable.
    exam_servers = []

    school_cache = {}

    potential_devices.each do |dev|
      begin
        conf = dev['puavoConf'][0]

        # quick-and-dirty rejection, without having to parse JSON
        unless conf.include?('"puavo.profiles.list"')
          next
        end

        conf = JSON.parse(conf)

        unless conf.include?('puavo.profiles.list')
          # the quick-and-dirty filtering failed for this device
          next
        end

        # if the profile list contains "ers", then this is an
        # Abitti exam server
        unless conf['puavo.profiles.list'].split(',').include?('ers')
          next
        end

        school_dn = dev['puavoSchool'][0]

        unless school_cache.include?(school_dn)
          begin
            school_cache[school_dn] = School.by_dn(school_dn)
          rescue StandardError => e
            rlog.error("School not found by DN '#{school_dn}', exam server '#{dev['puavoHostname'][0]}' ignored")
            next
          end
        end

        exam_servers << {
          device_id: dev['puavoId'][0].to_i,
          device_hostname: dev['puavoHostname'][0],
          school_id: school_cache[school_dn].id.to_i,
          school_abbr: school_cache[school_dn].abbreviation,
          school_name: school_cache[school_dn].name,
        }
      rescue StandardError => e
        rlog.error(e)
        next
      end
    end

    json exam_servers
  end


  # -------------------------------------------------------------------------------------------------
  # -------------------------------------------------------------------------------------------------
  # EXPERIMENTAL V4 API

  # Use at your own risk. Currently read-only.


  # Maps "user" field names to LDAP attributes. Used when searching for data, as only
  # the requested fields are actually returned in the queries.
  USER_TO_LDAP = {
    'allow_guest'             => 'puavoAllowGuest',
    'audio_in'                => 'puavoDeviceDefaultAudioSource',
    'audio_out'               => 'puavoDeviceDefaultAudioSink',
    'automatic_updates'       => 'puavoAutomaticImageUpdates',
    'autopoweroff_mode'       => 'puavoDeviceAutoPowerOffMode',
    'autopoweroff_off_hour'   => 'puavoDeviceOffHour',
    'autopoweroff_on_hour'    => 'puavoDeviceOnHour',
    'boot_mode'               => 'puavoDeviceBootMode',
    'created'                 => 'createTimestamp', # LDAP operational attribute
    'current_image'           => 'puavoDeviceCurrentImage',
    'default_printer'         => 'puavoDefaultPrinter',
    'description'             => 'description',
    'dn'                      => 'dn',
    'hostname'                => 'puavoHostname',
    'hw_info'                 => 'puavoDeviceHWInfo',
    'id'                      => 'puavoId',
    'image'                   => 'puavoDeviceImage',
    'image_series_url'        => 'puavoImageSeriesSourceURL',
    'kernel_args'             => 'puavoDeviceKernelArguments',
    'kernel_version'          => 'puavoDeviceKernelVersion',
    'location_lat'            => 'puavoLatitude',
    'location_lon'            => 'puavoLongitude',
    'location_name'           => 'puavoLocationName',
    'mac'                     => 'macAddress',
    'manufacturer'            => 'puavoDeviceManufacturer',
    'model'                   => 'puavoDeviceModel',
    'modified'                => 'modifyTimestamp', # LDAP operational attribute
    'monitors_xml'            => 'puavoDeviceMonitorsXML',
    'personal_device'         => 'puavoPersonalDevice',
    'personally_administered' => 'puavoPersonallyAdministered',
    'primary_user_id'         => 'puavoDevicePrimaryUser',
    'printer_queue'           => 'puavoPrinterQueue',
    'puavoconf'               => 'puavoConf',
    'purchase_date'           => 'puavoPurchaseDate',
    'purchase_location'       => 'puavoPurchaseLocation',
    'school_id'               => 'puavoSchool',
    'serial'                  => 'serialNumber',
    'status'                  => 'puavoDeviceStatus',
    'support_contract'        => 'puavoSupportContract',
    'tags'                    => 'puavoTag',
    'type'                    => 'puavoDeviceType',
    'xrandr'                  => 'puavoDeviceXrandr',
    'xserver'                 => 'puavoDeviceXserver',
  }

  # Maps LDAP attributes back to "user" fields and optionally specifies a conversion type
  LDAP_TO_USER = {
    'createTimestamp'               => { name: 'created', type: :ldap_timestamp },
    'description'                   => { name: 'description' },
    'dn'                            => { name: 'dn' },
    'macAddress'                    => { name: 'mac' },
    'modifyTimestamp'               => { name: 'modified', type: :ldap_timestamp },
    'puavoAllowGuest'               => { name: 'allow_guest', type: :boolean },
    'puavoAutomaticImageUpdates'    => { name: 'automatic_updates', type: :boolean },
    'puavoConf'                     => { name: 'puavoconf' },
    'puavoDefaultPrinter'           => { name: 'default_printer' },
    'puavoDeviceAutoPowerOffMode'   => { name: 'autopoweroff_mode' },
    'puavoDeviceBootMode'           => { name: 'boot_mode' },
    'puavoDeviceCurrentImage'       => { name: 'current_image' },
    'puavoDeviceDefaultAudioSink'   => { name: 'audio_out' },
    'puavoDeviceDefaultAudioSource' => { name: 'audio_in' },
    'puavoDeviceHWInfo'             => { name: 'hw_info' },
    'puavoDeviceImage'              => { name: 'image' },
    'puavoDeviceKernelArguments'    => { name: 'kernel_args' },
    'puavoDeviceKernelVersion'      => { name: 'kernel_version' },
    'puavoDeviceManufacturer'       => { name: 'manufacturer' },
    'puavoDeviceModel'              => { name: 'model' },
    'puavoDeviceMonitorsXML'        => { name: 'monitors_xml' },
    'puavoDeviceOffHour'            => { name: 'autopoweroff_off_hour', type: :integer },
    'puavoDeviceOnHour'             => { name: 'autopoweroff_on_hour', type: :integer },
    'puavoDevicePrimaryUser'        => { name: 'primary_user_id', type: :id_from_dn },
    'puavoDeviceStatus'             => { name: 'status' },
    'puavoDeviceType'               => { name: 'type' },
    'puavoDeviceXrandr'             => { name: 'xrandr' },
    'puavoDeviceXserver'            => { name: 'xserver' },
    'puavoHostname'                 => { name: 'hostname' },
    'puavoId'                       => { name: 'id', type: :integer },
    'puavoImageSeriesSourceURL'     => { name: 'image_series_url' },
    'puavoLatitude'                 => { name: 'location_lat' },
    'puavoLocationName'             => { name: 'location_name' },
    'puavoLongitude'                => { name: 'location_lon' },
    'puavoPersonalDevice'           => { name: 'personal_device', type: :boolean },
    'puavoPersonallyAdministered'   => { name: 'personally_administered', type: :boolean },
    'puavoPrinterQueue'             => { name: 'printer_queue' },
    'puavoPurchaseDate'             => { name: 'purchase_date' },
    'puavoPurchaseLocation'         => { name: 'purchase_location' },
    'puavoSchool'                   => { name: 'school_id', type: :id_from_dn },
    'puavoSupportContract'          => { name: 'support_contract' },
    'puavoTag'                      => { name: 'tags' },
    'serialNumber'                  => { name: 'serial' },
  }

  def v4_do_device_search(filters, requested_ldap_attrs)
    base = "ou=Devices,ou=Hosts,#{Organisation.current['base']}"
    filter_string = v4_combine_filter_parts(filters)

    return Device.raw_filter(base, filter_string, requested_ldap_attrs)
  end

  # Retrieve all (or some) devices in the organisation
  # GET /v4/devices?fields=...
  get '/v4/devices' do
    auth :basic_auth, :kerberos

    raise Unauthorized, :user => nil unless v4_is_request_allowed?(User.current)

    v4_do_operation do
      # which fields to get?
      user_fields = v4_get_fields(params).to_set
      ldap_attrs = v4_user_to_ldap(user_fields, USER_TO_LDAP)

      # optional filters
      filters = v4_get_filters_from_params(params, USER_TO_LDAP)

      # do the query
      raw = v4_do_device_search(filters, ldap_attrs)

      # convert and return
      out = v4_ldap_to_user(raw, ldap_attrs, LDAP_TO_USER)
      out = v4_ensure_is_array(out, 'mac', 'tags', 'xrandr', 'image_series_url')

      out.each do |o|
        if o.include?('puavoconf') && !o['puavoconf'].nil?
          o['puavoconf'] = JSON.parse(o['puavoconf'])
        end
      end

      return 200, json({
        status: 'ok',
        error: nil,
        data: out,
      })
    end
  end

end
end
