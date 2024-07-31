# Shared stuff between DevicesMassOperationsController, ServersMassOperationsController
# and SchoolsMassOperationsController. Included into the controllers, probably not
# useful/usable elsewhere.

# Ruby does not care about the object that's passed to these functions; as long as it
# has the requested member, everything's good. The object could be a Device, or a Server,
# or even... a School. Because there's a lot of overlap in their attributes.

# Not all objects have all the attributes. For example, schools don't have kernel arguments,
# and servers cannot be personally administrated. Trying to set an attribute on an object
# that does not have it will obviously fail, so don't do it.

module Puavo
  module CommonShared
    def set_database_field(object)
      changed = false

      value = @parameters['value']

      # Argh, there must be a better way to do this!
      case @parameters['field']
        when 'image'
          if object.puavoDeviceImage != value
            object.puavoDeviceImage = value
            changed = true
          end

        when 'kernelargs'
          if object.puavoDeviceKernelArguments != value
            object.puavoDeviceKernelArguments = value
            changed = true
          end

        when 'kernelversion'
          if object.puavoDeviceKernelVersion != value
            object.puavoDeviceKernelVersion = value
            changed = true
          end

        when 'puavoconf'
          if object.puavoConf != value
            object.puavoConf = value
            changed = true
          end

        when 'tags'
          if object.puavoTag != value
            object.puavoTag = value
            changed = true
          end

        when 'manufacturer'
          if object.puavoDeviceManufacturer != value
            object.puavoDeviceManufacturer = value
            changed = true
          end

        when 'model'
          if object.puavoDeviceModel != value
            object.puavoDeviceModel = value
            changed = true
          end

        when 'serial'
          if object.serialNumber != value
            object.serialNumber = value
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

          if object.puavoDevicePrimaryUser != value
            object.puavoDevicePrimaryUser = value
            changed = true
          end

        when 'description'
          if object.description != value
            object.description = value
            changed = true
          end

        when 'status'
          if value != object.puavoDeviceStatus
            object.puavoDeviceStatus = value
            changed = true
          end

        when 'location'
          if value != object.puavoLocationName
            object.puavoLocationName = value
            changed = true
          end

        when 'latitude'
          if value != object.puavoLatitude
            object.puavoLatitude = value
            changed = true
          end

        when 'longitude'
          if value != object.puavoLongitude
            object.puavoLongitude = value
            changed = true
          end

        when 'allow_guest'
          if value == -1 && object.puavoAllowGuest != nil
            object.puavoAllowGuest = nil
            changed = true
          elsif value == 0 && object.puavoAllowGuest != false
            object.puavoAllowGuest = false
            changed = true
          elsif value == 1 && object.puavoAllowGuest != true
            object.puavoAllowGuest = true
            changed = true
          end

        when 'personally_administered'
          if value == -1 && object.puavoPersonallyAdministered != nil
            object.puavoPersonallyAdministered = nil
            changed = true
          elsif value == 0 && object.puavoPersonallyAdministered != false
            object.puavoPersonallyAdministered = false
            changed = true
          elsif value == 1 && object.puavoPersonallyAdministered != true
            object.puavoPersonallyAdministered = true
            changed = true
          end

        when 'automatic_updates'
          if value == -1 && object.puavoAutomaticImageUpdates != nil
            object.puavoAutomaticImageUpdates = nil
            changed = true
          elsif value == 0 && object.puavoAutomaticImageUpdates != false
            object.puavoAutomaticImageUpdates = false
            changed = true
          elsif value == 1 && object.puavoAutomaticImageUpdates != true
            object.puavoAutomaticImageUpdates = true
            changed = true
          end

        when 'personal_device'
          if value == -1 && object.puavoPersonalDevice != nil
            object.puavoPersonalDevice = nil
            changed = true
          elsif value == 0 && object.puavoPersonalDevice != false
            object.puavoPersonalDevice = false
            changed = true
          elsif value == 1 && object.puavoPersonalDevice != true
            object.puavoPersonalDevice = true
            changed = true
          end

        when 'automatic_poweroff'
          if value != object.puavoDeviceAutoPowerOffMode
            object.puavoDeviceAutoPowerOffMode = value
            changed = true
          end

        when 'day_start'
          if value != object.puavoDeviceOnHour
            object.puavoDeviceOnHour = value
            changed = true
          end

        when 'day_end'
          if value != object.puavoDeviceOffHour
            object.puavoDeviceOffHour = value
            changed = true
          end

        when 'audio_source'
          if value != object.puavoDeviceDefaultAudioSource
            object.puavoDeviceDefaultAudioSource = value
            changed = true
          end

        when 'audio_sink'
          if value != object.puavoDeviceDefaultAudioSink
            object.puavoDeviceDefaultAudioSink = value
            changed = true
          end

        when 'printer_uri'
          if value != object.puavoPrinterDeviceURI
            object.puavoPrinterDeviceURI = value
            changed = true
          end

        when 'default_printer'
          if value != object.puavoDefaultPrinter
            object.puavoDefaultPrinter = value
            changed = true
          end

        when 'image_source_url'
          if value != object.puavoImageSeriesSourceURL
            object.puavoImageSeriesSourceURL = value
            changed = true
          end

        when 'xserver'
          if value != object.puavoDeviceXserver
            object.puavoDeviceXserver = value
            changed = true
          end

        when 'xrandr'
          if value != object.puavoDeviceXrandr
            object.puavoDeviceXrandr = value
            changed = true
          end

        when 'monitors_xml'
          if value != object.puavoDeviceMonitorsXML
            object.puavoDeviceMonitorsXML = value
            changed = true
          end

        else
          return [false, "unknown field \"#{@parameters['field']}\""]
      end

      object.save! if changed

      return [true, nil]
    end

    def puavoconf_edit(object)
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

      changed = false

      # New or existing configuration?
      conf = object.puavoConf ? JSON.parse(object.puavoConf) : {}

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
          object.puavoConf = nil
        else
          object.puavoConf = conf.to_json
        end

        object.save!
      end

      return [true, nil]
    end
  end
end
