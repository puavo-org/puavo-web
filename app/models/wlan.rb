module Wlan

  def validate_wlan_attributes
    wlan_names = Array( get_attribute("puavoWlanSSID") ).map { |ssid| ssid.split(":")[1] }
    if wlan_names.count != wlan_names.uniq.count
      errors.add( :puavoWlanSSID, I18n.t("activeldap.errors.messages.wlan.duplicate_name") )
    end
  end

  def update_wlan_attributes(wlan_name, wlan_type, wlan_password)
    max_index = wlan_name.keys.count - 1

    new_wlan_ssid = []

    (0..max_index).each do |index|
      next if wlan_name[index.to_s].empty?
      new_wlan_ssid.push( "#{ wlan_type[index.to_s] }:#{ wlan_name[index.to_s] }:#{ wlan_password[index.to_s] }" )
    end

    set_attribute( "puavoWlanSSID", new_wlan_ssid )
  end

  def wlan_name
    if wlan_ssid = get_attribute( "puavoWlanSSID" )
      Array(wlan_ssid).map{ |ssid| ssid.split(":")[1] }
    end
  end

  def wlan_type
    if wlan_ssid = get_attribute( "puavoWlanSSID" )
      Array(wlan_ssid).map{ |ssid| ssid.split(":")[0] }
    end
  end

  def wlan_password
    if wlan_ssid = get_attribute( "puavoWlanSSID" )
      Array(wlan_ssid).map{ |ssid| ssid.split(":")[2] }
    end
  end
end

