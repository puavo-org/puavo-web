require 'set'

module DevicesHelper
  include Puavo::Helpers

  def classes(device)
    classes = Device.allowed_classes

    classes.map do |r|
      "<div>" +
        "<label>" +
        "<input " +
        ( device.classes.include?(r) ? 'checked="checked"' : "" ) +
        "id='devices_#{r}' name='device[classes][]' type='checkbox' value='#{r}' />#{r}" +
        "</label>" +
        "</div>\n"
    end
  end

  def title(device)
    case true
    when device.classes.include?('puavoNetbootDevice')
      t('shared.terminal_title')
    when device.classes.include?('puavoPrinter')
      t('shared.printer_title')
    when device.classes.include?('puavoServer')
      t('shared.server_title')
    else
      t('shared.title')
    end
  end

  def model_name_from_ppd(ppd)
    return I18n.t('helpers.ppd_file.no_file') if ppd.nil?
    if match_data = ppd.match(/\*ModelName:(.*)\n/)
      return match_data[1].lstrip.gsub("\"", "")
    end
    return I18n.t('helpers.ppd_file.cannot_detect_filetype')
  end

  def self.get_device_attributes()
    return [
      'puavoId',
      'puavoHostname',
      'puavoDisplayName',
      'puavoDeviceType',
      'puavoDeviceImage',
      'puavoDeviceCurrentImage',
      'macAddress',
      'serialNumber',
      'puavoDeviceManufacturer',
      'puavoDeviceModel',
      'puavoDeviceKernelArguments',
      'puavoDeviceKernelVersion',
      'puavoDeviceMonitorsXML',
      'puavoDeviceXrandr',
      'puavoTag',
      'puavoConf',
      'description',
      'puavoNotes',
      'puavoDevicePrimaryUser',
      'puavoDeviceHWInfo',
      'puavoPurchaseDate',
      'puavoWarrantyEndDate',
      'puavoPurchaseLocation',
      'puavoPurchaseURL',
      'puavoSupportContract',
      'puavoLocationName',
      'puavoSchool',
      'puavoDeviceStatus',
      'puavoImageSeriesSourceURL',
      'puavoPrinterDeviceURI',
      'puavoDefaultPrinter',
      'puavoDeviceDefaultAudioSource',
      'puavoDeviceDefaultAudioSink',
      'puavoAllowGuest',
      'puavoPersonallyAdministered',
      'puavoAutomaticImageUpdates',
      'puavoPersonalDevice',
      'puavoLatitude',
      'puavoLongitude',
      'puavoTimezone',
      'puavoDeviceAutoPowerOffMode',
      'puavoDeviceOnHour',
      'puavoDeviceOffHour',
      'puavoDeviceReset',
      'authTimestamp',      # LDAP operational attribute
      'createTimestamp',    # LDAP operational attribute
      'modifyTimestamp'     # LDAP operational attribute
    ].freeze
  end

  # Retrieves a list of all devices in the specified school
  def self.get_devices_in_school(school_dn, custom_attributes=nil)
    return Device.search_as_utf8(:filter => "(puavoSchool=#{school_dn})",
                                 :scope => :one,
                                 :attributes => custom_attributes ? custom_attributes : DEVICE_ATTRIBUTES)
  end

  def self.get_server_attributes()
    return (self.get_device_attributes() + ["puavoDeviceAvailableImage"] - ["puavoDevicePrimaryUser"]).freeze
  end

  def self.format_device_primary_user(dn, school_id)
    begin
      u = User.find(dn)

      # The DN is valid
      return {
        valid: true,
        link: "/users/#{school_id}/users/#{u.id}",
        title: "#{u.uid} (#{u.givenName} #{u.sn})"
      }
    rescue
      # The DN is not valid, indicate it on the table
      return {
        valid: false,
        dn: dn,
      }
    end
  end

  def self.convert_raw_device(dev, releases)
    out = {}

    out[:id] = dev['puavoId'][0].to_i

    out[:hn] = dev['puavoHostname'][0]

    if dev.include?('puavoDisplayName')
      out[:display_name] = dev['puavoDisplayName'][0]
    end

    out[:type] = dev['puavoDeviceType'][0]

    if dev.include?('macAddress')
      a = Array(dev['macAddress'])

      if a.count > 0
        out[:mac] = a
      end
    end

    if dev.include?('serialNumber')
      out[:serial] = dev['serialNumber'][0]
    end

    if dev.include?('puavoDeviceManufacturer')
      out[:mfer] = dev['puavoDeviceManufacturer'][0]
    end

    if dev.include?('puavoDeviceModel')
      out[:model] = dev['puavoDeviceModel'][0]
    end

    if dev.include?('puavoTag')
      out[:tags] = dev['puavoTag']
    end

    if dev.include?('authTimestamp')
      out[:last_auth_time] = Puavo::Helpers::convert_ldap_time_pick_date(dev['authTimestamp'])
    end

    if dev.include?('createTimestamp')
      out[:created] = Puavo::Helpers::convert_ldap_time(dev['createTimestamp'])
    end

    if dev.include?('modifyTimestamp')
      out[:modified] = Puavo::Helpers::convert_ldap_time(dev['modifyTimestamp'])
    end

    if dev.include?('description')
      out[:desc] = dev['description'][0]
    end

    if dev.include?('puavoNotes')
      out[:notes] = dev['puavoNotes'][0]
    end

    if dev.include?('puavoDeviceKernelArguments')
      out[:krn_args] = dev['puavoDeviceKernelArguments'][0]
    end

    if dev.include?('puavoDeviceKernelVersion')
      out[:krn_ver] = dev['puavoDeviceKernelVersion'][0]
    end

    if dev.include?('puavoDeviceImage') && dev['puavoDeviceImage']
      out[:image] = Puavo::Helpers::get_release_name(dev['puavoDeviceImage'][0], releases)
    end

    if dev.include?('puavoDeviceXrandr')
      a = Array(dev['puavoDeviceXrandr'])

      if a.count > 0
        out[:xrandr] = a
      end
    end

    if dev.include?('puavoDeviceMonitorsXML')
      a = Array(dev['puavoDeviceMonitorsXML'])

      if a.count > 0
        out[:monitors_xml] = a
      end
    end

    if dev.include?('puavoConf')
      out[:conf] = JSON.parse(dev['puavoConf'][0]).collect{ |k, v| "#{k} = #{v}" }
    end

    if dev.include?('puavoDevicePrimaryUser')
      # We don't know yet if this DN is valid, it will be dealt with elsewhere
      out[:user] = dev['puavoDevicePrimaryUser'][0]
    end

    if dev.include?('puavoPurchaseDate')
      out[:purchase_date] = Puavo::Helpers::convert_ldap_time(dev['puavoPurchaseDate'])
    end

    if dev.include?('puavoWarrantyEndDate')
      out[:purchase_warranty] = Puavo::Helpers::convert_ldap_time(dev['puavoWarrantyEndDate'])
    end

    if dev.include?('puavoPurchaseLocation')
      out[:purchase_loc] = dev['puavoPurchaseLocation'][0]
    end

    if dev.include?('puavoPurchaseURL')
      out[:purchase_url] = dev['puavoPurchaseURL'][0]
    end

    if dev.include?('puavoSupportContract')
      out[:purchase_support] = dev['puavoSupportContract'][0]
    end

    if dev.include?('puavoLocationName')
      a = dev['puavoLocationName'][0].split("\n")

      if a.count > 0
        out[:location] = a
      end
    end

    if dev.include?('puavoLatitude')
      out[:loc_lat] = dev['puavoLatitude'][0]
    end

    if dev.include?('puavoLongitude')
      out[:loc_lon] = dev['puavoLongitude'][0]
    end

    if dev.include?('puavoDeviceStatus')
      out[:status] = dev['puavoDeviceStatus'][0]
    end

    if dev.include?('puavoDeviceAutoPowerOffMode')
      out[:autopower_mode] = dev['puavoDeviceAutoPowerOffMode'][0]
    end

    if dev.include?('puavoDeviceOnHour')
      out[:autopower_on] = dev['puavoDeviceOnHour'][0].to_i
    end

    if dev.include?('puavoDeviceOffHour')
      out[:autopower_off] = dev['puavoDeviceOffHour'][0].to_i
    end

    if dev.include?('puavoImageSeriesSourceURL')
      out[:image_series] = dev['puavoImageSeriesSourceURL']
    end

    if dev.include?('puavoPrinterDeviceURI')
      out[:printer_uri] = dev['puavoPrinterDeviceURI'][0]
    end

    if dev.include?('puavoDefaultPrinter')
      out[:default_printer] = dev['puavoDefaultPrinter'][0]
    end

    if dev.include?('puavoDeviceDefaultAudioSource')
      out[:audio_src] = dev['puavoDeviceDefaultAudioSource'][0]
    end

    if dev.include?('puavoDeviceDefaultAudioSink')
      out[:audio_sink] = dev['puavoDeviceDefaultAudioSink'][0]
    end

    if dev.include?('puavoAllowGuest')
      out[:allow_guest] = dev['puavoAllowGuest'][0] == 'TRUE'
    end

    if dev.include?('puavoPersonallyAdministered')
      out[:personal_admin] = dev['puavoPersonallyAdministered'][0] == 'TRUE'
    end

    if dev.include?('puavoAutomaticImageUpdates')
      out[:auto_updates] = dev['puavoAutomaticImageUpdates'][0] == 'TRUE'
    end

    if dev.include?('puavoPersonalDevice')
      out[:personal_device] = dev['puavoPersonalDevice'][0] == 'TRUE'
    end

    if dev.include?('puavoDeviceReset')
      reset = JSON.parse(dev['puavoDeviceReset'][0]) rescue {}

      out[:reset_from] = reset['from'] if reset.include?('from')
      out[:reset_pin] = reset['pin'].to_i if reset.include?('pin')
      out[:reset_operation] = reset['mode'] if reset.include?('mode')

      if reset.include?('request-time')
        begin
          out[:reset_time] = DateTime.parse(reset['request-time']).to_i
        rescue
        end
      end

      begin
        out[:reset_fulfilled] = DateTime.parse(reset['request-fulfilled']).to_i
      rescue
      end
    end

    # Parse the hardware information
    if dev.include?('puavoDeviceHWInfo')
      out.merge!(self.extract_hardware_info(dev['puavoDeviceHWInfo'][0], releases))
    end

    return out
  end

  def self.mangle_percentage_number(s)
    # A string containing a floating-point number, with a locate-specific digit separator
    # (dot, comma) and ending in a '%'. Convert it to a saner format.
    s.gsub(',', '.').gsub('%', '').to_f
  end

  def self.mangle_battery_voltage(s)
    # Like above, but replaces "V", not "%"
    s.gsub(',', '.').gsub('V', '').to_f
  end

  # Extracts the pieces we care about from puavoDeviceHWInfo field
  def self.extract_hardware_info(raw_hw_info, releases)
    megabytes = 1024 * 1024

    out = {}

    begin
      info = JSON.parse(raw_hw_info)

      # Receiving timestamp
      out[:hw_time] = info['timestamp'].to_i

      # We have puavoImage and puavoCurrentImage fields in the database, but
      # they aren't always reliable
      out[:current_image] = Puavo::Helpers::get_release_name(info['this_image'], releases)

      # For some reason, when I wrote the sysinfo collector tool back in 2017, I
      # used megabytes as the unit, instead of bytes. Too late to change that.
      out[:ram] = (info['memory'] || []).sum { |slot| slot['size'].to_i } * megabytes

      # Some machines have no memory slot info, so use the "raw" number instead
      if out[:ram] == 0
        out[:ram] = (info['memorysize_mb'] || 0).to_i * megabytes
      end

      out[:hd] = (info['blockdevice_sda_size'] || 0).to_i

      # Why oh why did I put a string in this field and not an integer?
      out[:hd_ssd] = info['ssd'] ? (info['ssd'] == '1') : false

      out[:have_smart] = info.include?('blockdevice_sda_smart') && !info['blockdevice_sda_smart'].nil?

      out[:wifi] = info['wifi']

      out[:bios_vendor] = info['bios_vendor']

      out[:bios_version] = info['bios_version']

      out[:bios_date] = info['bios_release_date']

      if info['processor0'] && info['processorcount']
        # combine CPU core count and name
        out[:cpu] = "#{info['processorcount']}×#{info['processor0']}"
      end

      if info['battery']
        out[:bat_vendor] = info['battery']['vendor']

        out[:bat_serial] = info['battery']['serial']

        if info['battery']['capacity']
          out[:bat_cap] = self.mangle_percentage_number(info['battery']['capacity']).to_i
        end

        if info['battery']['percentage']
          out[:bat_pcnt] = self.mangle_percentage_number(info['battery']['percentage']).to_i
        end

        if info['battery']['voltage']
          out[:bat_volts] = self.mangle_battery_voltage(info['battery']['voltage'])
        end
      end

      if info['extra_system_contents']
        extra = info['extra_system_contents']

        # Current Abitti version
        if extra['Abitti']
          out[:abitti_version] = extra['Abitti']
        end
      end

      # Free disk space on various partitions
      if info['free_space']
        df = info['free_space']

        out[:df_home] = df['/home'].to_i if df.include?('/home')
        out[:df_images] = df['/images'].to_i if df.include?('/home')
        out[:df_state] = df['/state'].to_i if df.include?('/home')
        out[:df_tmp] = df['/tmp'].to_i if df.include?('/home')
        out[:df_imageoverlays] = df['/imageoverlays'].to_i if df.include?('/imageoverlays')
      end

      # Windows license info (boolean exists/does not exist)
      out[:windows_license] = info.include?('windows_license') && !info['windows_license'].nil?
      out[:windows_installed] = info.fetch('windows', {}).fetch('is_installed', false)

      out[:lspci] = info['lspci_values']

      out[:lsusb] = info['lsusb_values']

      if info['logins'] && info['logins']['last']
        last = info['logins']['last']

        out[:ll_uid] = last['uid'] if last['uid']

        begin
          out[:ll_time] = Time.parse(last['timestamp']).to_i if last['timestamp']
        rescue
        end
      end

      if info['uptime']
        out[:uptime] = info['uptime']
      end

      if info['puavopkgs']
        out[:puavopkgs] = info['puavopkgs']
      end
    rescue => e
      # oh dear
      puts e
    end

    return out
  end

  def self.device_school_change_list(owner, user=nil, current_school_dn=nil)
    # Get a list of schools for the mass tool. I wanted to do this with AJAX
    # calls, getting the list from puavo-rest with the new V4 API, but fetch()
    # and CORS and other domains just won't cooperate...

    schools = School.search_as_utf8(:filter => '', :attributes => ['displayName', 'cn']).collect do |s|
        [s[0], s[1]['displayName'][0], s[1]['cn'][0]]
    end.sort do |a, b|
        # Sort alphabetically
        a[1].downcase <=> b[1].downcase
    end

    unless owner
      # School admins can only transfer devices between the schools they're admins of
      admin_schools = Set.new(Array(user.puavoAdminOfSchool || []).map { |dn| dn.to_s })
      schools.delete_if { |s| !admin_schools.include?(s[0]) }
    end

    if current_school_dn
      # Don't show the current school on the list. Not used on the organisation devices page.
      schools.delete_if { |s| s[0] == current_school_dn }
    end

    schools
  end

  # Resets (clears) the primary user of all devices this user is the primary user of.
  # Does not handle exceptions; if even one of the devices fail, the operation stops.
  def self.clear_device_primary_user(user_dn)
    Device.find(
      :all,
      attribute: 'puavoDevicePrimaryUser',
      value: user_dn.to_s
    ).each do |device|
      device.puavoDevicePrimaryUser = nil
      device.save!
    end
  end
end
