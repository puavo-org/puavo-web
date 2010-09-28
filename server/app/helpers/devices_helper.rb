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
    case @device.puavoDeviceType
    when 'thinclient' || 'fatclient'
      t('.terminal_title')
    when 'printer'
      t('.printer_title')
    else
      t('.title')
    end 
  end
end
