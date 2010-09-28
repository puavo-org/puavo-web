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

  def title
    case true
    when @device.classes.include?('puavoNetbootDevice')
      t('.terminal_title')
    when @device.classes.include?('puavoPrinter')
      t('.printer_title')
    else
      t('.title')
    end 
  end

  def device_type(form)
    device_types = PUAVO_CONFIG['allow_change_device_types']
    if device_types.include?(@device.puavoDeviceType)
      form.label(:puavoDeviceType) +
        tag('br') + 
        form.select( :puavoDeviceType,
                     device_types.map{ |d| [PUAVO_CONFIG['device_types'][d]['label'][I18n.locale.to_s], d] } )
    else
      form.label(:puavoDeviceType) + " " +
        PUAVO_CONFIG['device_types'][@device.puavoDeviceType]['label'][I18n.locale.to_s]
    end
  end
end
