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

  def device_type(form)
    device_types = PUAVO_CONFIG['allow_change_device_types']
    if device_types.include?(form.object.puavoDeviceType)
      form.label(:puavoDeviceType) +
        tag('br') + 
        form.select( :puavoDeviceType,
                     device_types.map{ |d| [PUAVO_CONFIG['device_types'][d]['label'][I18n.locale.to_s], d] } )
    end
  end
end
