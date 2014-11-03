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

end
