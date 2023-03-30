# All devices-related mass operations

class DevicesMassOperationsController < MassOperationsController
  # POST '/devices_mass_operation'
  def devices_mass_operation
    prepare

    result = process_rows do |id, data|
      puts "[#{@request_id}] Processing item #{id}, item data=#{data.inspect}"

      case @operation
        when 'set_field'
          _set_database_field(id)

        when 'purchase_info'
          _change_purchase_info(id, data)

        when 'puavoconf_edit'
          _puavoconf_edit(id)

        when 'change_school'
          _change_school(id)

        when 'reset'
          _reset(id)

        when 'delete'
          _delete(id)

        else
          next false, "Unknown operation \"#{@operation}\""
      end
    end

    render json: result
  rescue StandardError => e
    render json: { ok: false, message: e, request_id: @request_id }
  end

  private

  def _set_database_field(device_id)
    device = Device.find(device_id)
    changed = false

    value = @parameters['value']

    # Argh, there must be a better way to do this!
    case @parameters['field']
      when 'image'
        if device.puavoDeviceImage != value
          device.puavoDeviceImage = value
          changed = true
        end

      when 'kernelargs'
        if device.puavoDeviceKernelArguments != value
          device.puavoDeviceKernelArguments = value
          changed = true
        end

      when 'kernelversion'
        if device.puavoDeviceKernelVersion != value
          device.puavoDeviceKernelVersion = value
          changed = true
        end

      when 'puavoconf'
        if device.puavoConf != value
          device.puavoConf = value
          changed = true
        end

      when 'tags'
        if device.puavoTag != value
          device.puavoTag = value
          changed = true
        end

      when 'manufacturer'
        if device.puavoDeviceManufacturer != value
          device.puavoDeviceManufacturer = value
          changed = true
        end

      when 'model'
        if device.puavoDeviceModel != value
          device.puavoDeviceModel = value
          changed = true
        end

      when 'serial'
        if device.serialNumber != value
          device.serialNumber = value
          changed = true
        end

      when 'primary_user'
        if value.nil? || value.empty?
          # Allow the primary user to be cleared
          value = nil
        else
          # Convert the username to a DN
          user = User.find(:first, :attribute => "uid", :value => value)

          if user.nil?
            return [false, t('devices.index.mass_operations.set_field.unknown_user', { name: value })]
          end

          value = user.dn.to_s
        end

        if device.puavoDevicePrimaryUser != value
          device.puavoDevicePrimaryUser = value
          changed = true
        end

      when 'description'
        if device.description != value
          device.description = value
          changed = true
        end

      when 'status'
        if value != device.puavoDeviceStatus
          device.puavoDeviceStatus = value
          changed = true
        end

      when 'location'
        if value != device.puavoLocationName
          device.puavoLocationName = value
          changed = true
        end

      when 'latitude'
        if value != device.puavoLatitude
          device.puavoLatitude = value
          changed = true
        end

      when 'longitude'
        if value != device.puavoLongitude
          device.puavoLongitude = value
          changed = true
        end

      when 'allow_guest'
        if value == -1 && device.puavoAllowGuest != nil
          device.puavoAllowGuest = nil
          changed = true
        elsif value == 0 && device.puavoAllowGuest != false
          device.puavoAllowGuest = false
          changed = true
        elsif value == 1 && device.puavoAllowGuest != true
          device.puavoAllowGuest = true
          changed = true
        end

      when 'personally_administered'
        if value == -1 && device.puavoPersonallyAdministered != nil
          device.puavoPersonallyAdministered = nil
          changed = true
        elsif value == 0 && device.puavoPersonallyAdministered != false
          device.puavoPersonallyAdministered = false
          changed = true
        elsif value == 1 && device.puavoPersonallyAdministered != true
          device.puavoPersonallyAdministered = true
          changed = true
        end

      when 'automatic_updates'
        if value == -1 && device.puavoAutomaticImageUpdates != nil
          device.puavoAutomaticImageUpdates = nil
          changed = true
        elsif value == 0 && device.puavoAutomaticImageUpdates != false
          device.puavoAutomaticImageUpdates = false
          changed = true
        elsif value == 1 && device.puavoAutomaticImageUpdates != true
          device.puavoAutomaticImageUpdates = true
          changed = true
        end

      when 'personal_device'
        if value == -1 && device.puavoPersonalDevice != nil
          device.puavoPersonalDevice = nil
          changed = true
        elsif value == 0 && device.puavoPersonalDevice != false
          device.puavoPersonalDevice = false
          changed = true
        elsif value == 1 && device.puavoPersonalDevice != true
          device.puavoPersonalDevice = true
          changed = true
        end

      when 'automatic_poweroff'
        if value != device.puavoDeviceAutoPowerOffMode
          device.puavoDeviceAutoPowerOffMode = value
          changed = true
        end

      when 'daytime_start'
        if value != device.puavoDeviceOnHour
          device.puavoDeviceOnHour = value
          changed = true
        end

      when 'daytime_end'
        if value != device.puavoDeviceOffHour
          device.puavoDeviceOffHour = value
          changed = true
        end

      when 'audio_source'
        if value != device.puavoDeviceDefaultAudioSource
          device.puavoDeviceDefaultAudioSource = value
          changed = true
        end

      when 'audio_sink'
        if value != device.puavoDeviceDefaultAudioSink
          device.puavoDeviceDefaultAudioSink = value
          changed = true
        end

      when 'printer_uri'
        if value != device.puavoPrinterDeviceURI
          device.puavoPrinterDeviceURI = value
          changed = true
        end

      when 'default_printer'
        if value != device.puavoDefaultPrinter
          device.puavoDefaultPrinter = value
          changed = true
        end

      when 'image_source_url'
        if value != device.puavoImageSeriesSourceURL
          device.puavoImageSeriesSourceURL = value
          changed = true
        end

      when 'xserver'
        if value != device.puavoDeviceXserver
          device.puavoDeviceXserver = value
          changed = true
        end

      when 'monitors_xml'
        if value != device.puavoDeviceMonitorsXML
          device.puavoDeviceMonitorsXML = value
          changed = true
        end

      else
        return [false, "unknown field \"#{@parameters['field']}\""]
    end

    device.save! if changed

    return [true, nil]
  end

  def _change_purchase_info(device_id, data)
    device = Device.find(device_id)
    changed = false

    if data.include?('purchase_date')
      old_date = device.puavoPurchaseDate ? device.puavoPurchaseDate.strftime('%Y-%m-%d') : nil
      new_date = @parameters['purchase_date']

      if old_date != new_date
        device.puavoPurchaseDate = new_date ? Time.strptime("#{new_date} 00:00:00 UTC", '%Y-%m-%d %H:%M:%S %Z') : nil
        changed = true
      end
    end

    if data.include?('warranty_end_date')
      old_date = device.puavoPurchaseDate ? device.puavoWarrantyEndDate.strftime('%Y-%m-%d') : nil
      new_date = @parameters['warranty_end_date']

      if old_date != new_date
        device.puavoWarrantyEndDate = new_date ? Time.strptime("#{new_date} 00:00:00 UTC", '%Y-%m-%d %H:%M:%S %Z') : nil
        changed = true
      end
    end

    if data.include?('purchase_location') && device.puavoPurchaseLocation != @parameters['purchase_location']
      device.puavoPurchaseLocation = @parameters['purchase_location']
      changed = true
    end

    if data.include?('purchase_url') && device.puavoPurchaseURL != @parameters['purchase_url']
      device.puavoPurchaseURL = @parameters['purchase_url']
      changed = true
    end

    if data.include?('support_contract') && device.puavoSupportContract != @parameters['support_contract']
      device.puavoSupportContract = @parameters['support_contract']
      changed = true
    end

    device.save! if changed

    return [true, nil]
  end

  def _puavoconf_edit(device_id)
    # Interpret the value
    case @parameters['type']
      when 'string'
        value = @parameters['value'].to_s   # ensure it really is a string

      when 'int'
        value = @parameters['value'].to_i(10)

      when 'bool'
        # Seriously? Is this really how I'm going to roll? Okay then.
        if @parameters['value'] == 'true'
          value = true
        elsif @parameters['value'] == 'false'
          value = false
        else
          # non-zero is true
          value = (@parameters['value'].to_i == 0) ? false : true
        end

      else
        return [false, "unknown datatype \"#{@parameters['type']}\""]
    end

    device = Device.find(device_id)
    changed = false

    # New or existing configuration?
    conf = device.puavoConf ? JSON.parse(device.puavoConf) : {}

    key = @parameters['key']

    case @parameters['action']
      when 'add'
        if conf.include?(key)
          if conf[key] != value
            conf[key] = value
            changed = true
          end
        else
          conf[key] = value
          changed = true
        end

      when 'remove'
        if conf.include?(key)
          conf.delete(key)
          changed = true
        end
    end

    if changed
      if conf.empty?
        # Empty hash serializes as "{}" in JSON, but that's not what we want
        device.puavoConf = nil
      else
        device.puavoConf = conf.to_json
      end

      device.save!
    end

    return [true, nil]
  end

  def _change_school(device_id)
    device = Device.find(device_id)

    if device.puavoSchool.to_s != @parameters['school_dn']
      device.puavoSchool = @parameters['school_dn']
      device.save!
    end

    return [true, nil]
  end

  def _reset(device_id)
    device = Device.find(device_id)
    changed = false

    unless device.puavoDeviceType == 'laptop'
      # The client does this same check, but do it again, just in case
      return [false, t('devices.index.mass_operations.reset.not_a_laptop')]
    end

    if @parameters['reset'] && !device.puavoDeviceReset
      # Set
      device.set_reset_mode(current_user)
      device.save!
    elsif !@parameters['reset'] && device.puavoDeviceReset
      # Clear
      device.puavoDeviceReset = nil
      device.save!
    end

    return [true, nil]
  end

  def _delete(device_id)
    device = Device.find(device_id)
    device.destroy

    if Puavo::CONFIG['inventory_management']
      # Notify the external inventory management
      Puavo::Inventory::device_deleted(logger, Puavo::CONFIG['inventory_management'], device_id)
    end

    return [true, nil]
  end
end
