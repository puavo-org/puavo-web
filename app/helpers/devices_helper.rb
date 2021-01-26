module DevicesHelper

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

  # Converts LDAP operational timestamp attribute (received with search_as_utf8() call)
  # to unixtime. Expects the timestamp to be nil or a single-element array. Used in
  # users, groups and devices controllers when retrieving data with AJAX calls.
  # TODO: GET RID OF THIS FUNCTION. It was copy-pasted from application_helper.rb because
  # I can't get Ruby to find it from there. Argh!
  def self.convert_ldap_time(t)
    return nil unless t
    Time.strptime(t[0], '%Y%m%d%H%M%S%z').to_i
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

  # Retrieves a list of all devices in the specified school
  def self.get_devices_in_school(school_dn, custom_attributes=nil)
    return Device.search_as_utf8(:filter => "(puavoSchool=#{school_dn})",
                                 :scope => :one,
                                 :attributes => custom_attributes ? custom_attributes : DEVICE_ATTRIBUTES)
  end

  def self.build_common_device_properties(dev)
    # Localise device type names. We can do this in the JavaScript code too, but the table
    # sorter only sees IDs, not names, so it sorts device types incorrerctly.
    device_types = Puavo::CONFIG['device_types']

    return {
      id: dev['puavoId'][0].to_i,
      hn: dev['puavoHostname'][0],
      type: dev['puavoDeviceType'] ? device_types[dev['puavoDeviceType'][0]]['label'][I18n.locale.to_s] : nil,
      image: dev['puavoDeviceImage'] ? dev['puavoDeviceImage'][0] : nil,
      mac: dev['macAddress'] ? Array(dev['macAddress']) : nil,
      serial: dev['serialNumber'] ? dev['serialNumber'][0] : nil,
      mfer: dev['puavoDeviceManufacturer'] ? dev['puavoDeviceManufacturer'][0] : nil,
      model: dev['puavoDeviceModel'] ? dev['puavoDeviceModel'][0] : nil,
      desc: dev['description'] ? dev['description'][0] : nil,
      krn_args: dev['puavoDeviceKernelArguments'] ? dev['puavoDeviceKernelArguments'][0] : nil,
      krn_ver: dev['puavoDeviceKernelVersion'] ? dev['puavoDeviceKernelVersion'][0] : nil,
      tags: dev['puavoTag'] ? dev['puavoTag'] : nil,
      created: self.convert_ldap_time(dev['createTimestamp']),
      modified: self.convert_ldap_time(dev['modifyTimestamp']),
      xrandr: dev['puavoDeviceXrandr'] ? Array(dev['puavoDeviceXrandr']) : nil,
      monitors_xml: dev['puavoDeviceMonitorsXML'] ? Array(dev['puavoDeviceMonitorsXML']) : nil,
      user: dev['puavoDevicePrimaryUser'] ? dev['puavoDevicePrimaryUser'] : nil,
      conf: dev['puavoConf'] ? JSON.parse(dev['puavoConf'][0]).collect{|k, v| "\"#{k}\"=\"#{v}\"" } : nil,
      purchase_date: dev['puavoPurchaseDate'] ? self.convert_ldap_time(dev['puavoPurchaseDate']) : nil,
      purchase_warranty: dev['puavoWarrantyEndDate'] ? self.convert_ldap_time(dev['puavoWarrantyEndDate']) : nil,
      purchase_loc: dev['puavoPurchaseLocation'] ? dev['puavoPurchaseLocation'][0] : nil,
      purchase_url: dev['puavoPurchaseURL'] ? dev['puavoPurchaseURL'][0] : nil,
      purchase_support: dev['puavoSupportContract'] ? dev['puavoSupportContract'][0] : nil,
      location: dev['puavoLocationName'] ? dev['puavoLocationName'][0] : nil,
    }
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
  def self.extract_hardware_info(raw_hw_info)
    megabytes = 1024 * 1024
    gigabytes = megabytes * 1024

    out = {}

    begin
      info = JSON.parse(raw_hw_info[0])

      # we have puavoImage and puavoCurrentImage fields in the database, but
      # they aren't always reliable
      out[:current_image] = info['this_image']

      out[:hw_time] = info['timestamp'].to_i
      out[:ram] = (info['memory'] || []).sum { |slot| slot['size'].to_i }

      # Some machines have no memory slot info, so use the "raw" number instead
      out[:ram] = (info['memorysize_mb'] || 0).to_i if out[:ram] == 0

      out[:hd] = ((info['blockdevice_sda_size'] || 0).to_i / megabytes).to_i
      out[:hd_ssd] = info['ssd'] ? (info['ssd'] == '1') : false   # why oh why did I put a string in this field and not an integer?
      out[:wifi] = info['wifi']
      out[:bios_vendor] = info['bios_vendor']
      out[:bios_version] = info['bios_version']
      out[:bios_date] = info['bios_release_date']

      if info['processor0'] && info['processorcount']
        # combine CPU count and name
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

      # Current Abitti version
      if info['extra_system_contents']
        extra = info['extra_system_contents']

        if extra['Abitti']
          out[:abitti_version] = extra['Abitti'].to_i || -1
        end
      end

      # Free disk space on various partitions
      if info['free_space']
        df = info['free_space']

        out[:df_home] = df.include?('/home') ? (df['/home'].to_i / megabytes) : nil
      end
    rescue
      # oh well
    end

    # Windows license info (boolean exists/does not exist)
    if info.include?('windows_license') && !info['windows_license'].nil?
      out[:winlic] = true
    else
      out[:winlic] = false
    end

    return out
  end

end
