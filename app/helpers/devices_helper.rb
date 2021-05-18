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

  def is_device_change_allowed(form)
    Puavo::CONFIG['allow_change_device_types'].include?(form.object.puavoDeviceType)
  end

  def device_type(form)
    device_types = Puavo::CONFIG['allow_change_device_types']
    form.select( :puavoDeviceType,
                 device_types.map{ |d| [Puavo::CONFIG['device_types'][d]['label'][I18n.locale.to_s], d] } )
  end

  def model_name_from_ppd(ppd)
    return I18n.t('helpers.ppd_file.no_file') if ppd.nil?
    if match_data = ppd.match(/\*ModelName:(.*)\n/)
      return match_data[1].lstrip.gsub("\"", "")
    end
    return I18n.t('helpers.ppd_file.cannot_detect_filetype')
  end

  DEVICE_ATTRIBUTES = [
    'puavoId',
    'puavoHostname',
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
    'puavoDevicePrimaryUser',
    'puavoDeviceHWInfo',
    'puavoPurchaseDate',
    'puavoWarrantyEndDate',
    'puavoPurchaseLocation',
    'puavoPurchaseURL',
    'puavoSupportContract',
    'puavoLocationName',
    'createTimestamp',    # LDAP operational attribute
    'modifyTimestamp'     # LDAP operational attribute
  ]

  # If any of these columns are requested, then we have to parse the hwinfo JSON
  HWINFO_ATTRS = Set.new([
    "abitti_version",
    "hw_time",
    "ram",
    "hd",
    "hd_ssd",
    "df_home",
    "df_images",
    "df_state",
    "df_tmp",
    "cpu",
    "current_image",
    "bio_vendor",
    "bios_version",
    "bios_date",
    "bat_vendor",
    "bat_serial",
    "bat_cap",
    "bat_pcnt",
    "bat_volts",
    "windows_license",
    "wifi"
  ]).freeze

  def self.convert_requested_device_column_names(requested)
    attributes = []

    attributes << 'puavoId' if requested.include?('id')
    attributes << 'puavoHostname' if requested.include?('hn')
    attributes << 'puavoDeviceType' if requested.include?('type')
    attributes << 'puavoTag' if requested.include?('tags')
    attributes << 'puavoDeviceManufacturer' if requested.include?('mfer')
    attributes << 'puavoDeviceModel' if requested.include?('model')
    attributes << 'serialNumber' if requested.include?('serial')
    attributes << 'macAddress' if requested.include?('mac')
    attributes << 'description' if requested.include?('desc')
    attributes << 'puavoDeviceImage' if requested.include?('image')
    attributes << 'puavoDeviceCurrentImage' if requested.include?('current_image')
    attributes << 'puavoDeviceKernelArguments' if requested.include?('krn_args')
    attributes << 'puavoDeviceKernelVersion' if requested.include?('krn_ver')
    attributes << 'createTimestamp' if requested.include?('created')
    attributes << 'modifyTimestamp' if requested.include?('modified')
    attributes << 'puavoConf' if requested.include?('conf')
    attributes << 'puavoDevicePrimaryUser' if requested.include?('user')
    attributes << 'puavoDeviceMonitorsXML' if requested.include?('monitors_xml')
    attributes << 'puavoDeviceXrandr' if requested.include?('xrandr')
    attributes << 'puavoPurchaseDate' if requested.include?('purchase_date')
    attributes << 'puavoWarrantyEndDate' if requested.include?('purchase_warranty')
    attributes << 'puavoPurchaseLocation' if requested.include?('purchase_loc')
    attributes << 'puavoPurchaseURL' if requested.include?('purchase_url')
    attributes << 'puavoSupportContract' if requested.include?('purchase_support')
    attributes << 'puavoLocationName' if requested.include?('location')

    return attributes
  end

  def self.convert_requested_hwinfo_column_names(requested)
    attributes = []

    attributes << :abitti_version if requested.include?('abitti_version')
    attributes << :hw_time if requested.include?('hw_time')
    attributes << :ram if requested.include?('ram')
    attributes << :hd if requested.include?('hd')
    attributes << :hd_ssd if requested.include?('hd_ssd')
    attributes << :df_home if requested.include?('df_home')
    attributes << :df_images if requested.include?('df_images')
    attributes << :df_state if requested.include?('df_state')
    attributes << :df_tmp if requested.include?('df_tmp')
    attributes << :current_image if requested.include?('current_image')
    attributes << :cpu if requested.include?('cpu')
    attributes << :bios_vendor if requested.include?('bios_vendor')
    attributes << :bios_version if requested.include?('bios_version')
    attributes << :bios_date if requested.include?('bios_date')
    attributes << :bat_vendor if requested.include?('bat_vendor')
    attributes << :bat_serial if requested.include?('bat_serial')
    attributes << :bat_cap if requested.include?('bat_cap')
    attributes << :bat_pcnt if requested.include?('bat_pcnt')
    attributes << :bat_volts if requested.include?('bat_volts')
    attributes << :windows_license if requested.include?('windows_license')
    attributes << :wifi if requested.include?('wifi')

    attributes
  end

  # Retrieves a list of all devices in the specified school
  def self.get_devices_in_school(school_dn, custom_attributes=nil)
    return Device.search_as_utf8(:filter => "(puavoSchool=#{school_dn})",
                                 :scope => :one,
                                 :attributes => custom_attributes ? custom_attributes : DEVICE_ATTRIBUTES)
  end

  def self.build_common_device_properties(dev, requested)
    d = {}

    if requested.include?('mac')
      d[:mac] = dev['macAddress'] ? Array(dev['macAddress']) : nil
    end

    if requested.include?('serial')
      d[:serial] = dev['serialNumber'] ? dev['serialNumber'][0] : nil
    end

    if requested.include?('mfer')
      d[:mfer] = dev['puavoDeviceManufacturer'] ? dev['puavoDeviceManufacturer'][0] : nil
    end

    if requested.include?('model')
      d[:model] = dev['puavoDeviceModel'] ? dev['puavoDeviceModel'][0] : nil
    end

    if requested.include?('tags')
      d[:tags] = dev['puavoTag'] ? dev['puavoTag'] : nil
    end

    if requested.include?('created')
      d[:created] = Puavo::Helpers::convert_ldap_time(dev['createTimestamp'])
    end

    if requested.include?('modified')
      d[:modified] = Puavo::Helpers::convert_ldap_time(dev['modifyTimestamp'])
    end

    if requested.include?('desc')
      d[:desc] = dev['description'] ? dev['description'][0] : nil
    end

    if requested.include?('krn_args')
      d[:krn_args] = dev['puavoDeviceKernelArguments'] ? dev['puavoDeviceKernelArguments'][0] : nil
    end

    if requested.include?('krn_ver')
      d[:krn_ver] = dev['puavoDeviceKernelVersion'] ? dev['puavoDeviceKernelVersion'][0] : nil
    end

    if requested.include?('image')
      d[:image] = dev['puavoDeviceImage'] ? dev['puavoDeviceImage'] : nil
    end

    if requested.include?('xrandr')
      d[:xrandr] = dev['puavoDeviceXrandr'] ? Array(dev['puavoDeviceXrandr']) : nil
    end

    if requested.include?('monitors_xml')
      d[:monitors_xml] = dev['puavoDeviceMonitorsXML'] ? Array(dev['puavoDeviceMonitorsXML']) : nil
    end

    if requested.include?('conf')
      d[:conf] = dev['puavoConf'] ? JSON.parse(dev['puavoConf'][0]).collect{|k, v| "\"#{k}\"=\"#{v}\"" } : nil
    end

    if requested.include?('user')
      d[:user] = dev['puavoDevicePrimaryUser'] ? dev['puavoDevicePrimaryUser'][0] : nil
    end

    if requested.include?('purchase_date')
      d[:purchase_date] = dev['puavoPurchaseDate'] ? Puavo::Helpers::convert_ldap_time(dev['puavoPurchaseDate']) : nil
    end

    if requested.include?('purchase_warranty')
      d[:purchase_warranty] = dev['puavoWarrantyEndDate'] ? Puavo::Helpers::convert_ldap_time(dev['puavoWarrantyEndDate']) : nil
    end

    if requested.include?('purchase_loc')
      d[:purchase_loc] = dev['puavoPurchaseLocation'] ? dev['puavoPurchaseLocation'][0] : nil
    end

    if requested.include?('purchase_url')
      d[:purchase_url] = dev['puavoPurchaseURL'] ? dev['puavoPurchaseURL'][0] : nil
    end

    if requested.include?('purchase_support')
      d[:purchase_support] = dev['puavoSupportContract'] ? dev['puavoSupportContract'][0] : nil
    end

    if requested.include?('location')
      d[:location] = dev['puavoLocationName'] ? dev['puavoLocationName'][0] : nil
    end

    return d
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
  def self.extract_hardware_info(raw_hw_info, requested)
    megabytes = 1024 * 1024
    gigabytes = megabytes * 1024

    out = {}

    begin
      info = JSON.parse(raw_hw_info[0])

      if requested.include?(:hw_time)
        out[:hw_time] = info['timestamp'].to_i
      end

      # we have puavoImage and puavoCurrentImage fields in the database, but
      # they aren't always reliable
      out[:current_image] = info['this_image']

      if requested.include?(:ram)
        out[:ram] = (info['memory'] || []).sum { |slot| slot['size'].to_i }

        # Some machines have no memory slot info, so use the "raw" number instead
        out[:ram] = (info['memorysize_mb'] || 0).to_i if out[:ram] == 0
      end

      if requested.include?(:hd)
        out[:hd] = ((info['blockdevice_sda_size'] || 0).to_i / megabytes).to_i
      end

      if requested.include?(:hd_ssd)
        out[:hd_ssd] = info['ssd'] ? (info['ssd'] == '1') : false   # why oh why did I put a string in this field and not an integer?
      end

      if requested.include?(:wifi)
        out[:wifi] = info['wifi']
      end

      if requested.include?(:bios_vendor)
        out[:bios_vendor] = info['bios_vendor']
      end

      if requested.include?(:bios_version)
        out[:bios_version] = info['bios_version']
      end

      if requested.include?(:bios_date)
        out[:bios_date] = info['bios_release_date']
      end

      if requested.include?(:cpu)
        if info['processor0'] && info['processorcount']
          # combine CPU core count and name
          out[:cpu] = "#{info['processorcount']}×#{info['processor0']}"
        end
      end

      if info['battery']
        if requested.include?(:bat_vendor)
          out[:bat_vendor] = info['battery']['vendor']
        end

        if requested.include?(:bat_serial)
          out[:bat_serial] = info['battery']['serial']
        end

        if requested.include?(:bat_cap) && info['battery']['capacity']
          out[:bat_cap] = self.mangle_percentage_number(info['battery']['capacity']).to_i
        end

        if requested.include?(:bat_pcnt) && info['battery']['percentage']
          out[:bat_pcnt] = self.mangle_percentage_number(info['battery']['percentage']).to_i
        end

        if requested.include?(:bat_volts) && info['battery']['voltage']
          out[:bat_volts] = self.mangle_battery_voltage(info['battery']['voltage'])
        end
      end

      if requested.include?(:abitti_version)
        # Current Abitti version
        if info['extra_system_contents']
          extra = info['extra_system_contents']

          if extra['Abitti']
            out[:abitti_version] = extra['Abitti']
          end
        end
      end

      if requested.include?(:df_home) || requested.include?(:df_images) ||
         requested.include?(:df_state) || requested.include?(:df_tmp)
        # Free disk space on various partitions. Retrieve them all even if only one
        # of them was requested, because it takes a lot of effort to dig them up.
        if info['free_space']
          df = info['free_space']

          out[:df_home] = df.include?('/home') ? (df['/home'].to_i / megabytes) : nil
          out[:df_images] = df.include?('/images') ? (df['/images'].to_i / megabytes) : nil
          out[:df_state] = df.include?('/state') ? (df['/state'].to_i / megabytes) : nil
          out[:df_tmp] = df.include?('/tmp') ? (df['/tmp'].to_i / megabytes) : nil
        end
      end
    rescue
      # oh well
    end

    if requested.include?(:windows_license)
      # Windows license info (boolean exists/does not exist)
      if info.include?('windows_license') && !info['windows_license'].nil?
        out[:windows_license] = true
      else
        out[:windows_license] = false
      end
    end

    return out
  end

  def self.device_school_change_list
    # Get a list of schools for the mass tool. I wanted to do this with AJAX
    # calls, getting the list from puavo-rest with the new V4 API, but fetch()
    # and CORS and other domains just won't cooperate...
    School.search_as_utf8(:filter => '', :attributes => ['displayName', 'cn']).collect do |s|
        [s[0], s[1]['displayName'][0], s[1]['cn'][0]]
    end.sort do |a, b|
        a[1].downcase <=> b[1].downcase
    end
  end
end
