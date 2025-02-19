# All devices-related mass operations

class DevicesMassOperationsController < MassOperationsController
  include Puavo::CommonShared

  # POST '/devices_mass_operation'
  def devices_mass_operation
    prepare

    result = process_rows do |id, data|
      logger.info "[#{@request_id}] Processing item #{id}, item data=#{data.inspect}"

      case @operation
        when 'set_field'
          # This comes from Puavo::CommonShared
          set_database_field(Device.find(id))

        when 'purchase_info'
          _change_purchase_info(id, data)

        when 'puavoconf_edit'
          # This comes from Puavo::CommonShared
          puavoconf_edit(Device.find(id))

        when 'tags_edit'
          # This comes from Puavo::CommonShared
          tags_edit(Device.find(id))

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
      old_date = device.puavoWarrantyEndDate ? device.puavoWarrantyEndDate.strftime('%Y-%m-%d') : nil
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
  rescue StandardError => e
    logger.info "[#{@request_id}] Mass operation failed: #{e}"
    return [false, nil]
  end

  def _change_school(device_id)
    device = Device.find(device_id)

    if device.puavoSchool.to_s != @parameters['school_dn']
      device.puavoSchool = @parameters['school_dn']
      device.save!
      if Puavo::CONFIG['inventory_management']
        # Notify the external inventory management
        Puavo::Inventory::device_modified(logger, Puavo::CONFIG['inventory_management'], device, current_organisation.organisation_key)
      end
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
