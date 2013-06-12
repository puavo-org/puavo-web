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
      new_wlan_ssid.push( { :ssid => wlan_name[index.to_s],
                            :type => wlan_type[index.to_s],
                            :password => wlan_password[index.to_s] }.to_json  )
    end

    set_attribute( "puavoWlanSSID", new_wlan_ssid )
  end

  def wlan_name
    if wlan_ssid = get_attribute( "puavoWlanSSID" )
      begin
        Array(wlan_ssid).map{ |ssid| JSON.parse(ssid)["ssid"] }
      rescue JSON::ParserError => e
        logger.info "Invalid puavoWlanSSID value"
        return []
      end
    end
  end

  def wlan_type
    if wlan_ssid = get_attribute( "puavoWlanSSID" )
      begin
        Array(wlan_ssid).map{ |ssid| JSON.parse(ssid)["type"] }
      rescue JSON::ParserError => e
        logger.info "Invalid puavoWlanSSID value"
        return []
      end
    end
  end

  def wlan_password
    if wlan_ssid = get_attribute( "puavoWlanSSID" )
      begin
        Array(wlan_ssid).map{ |ssid| JSON.parse(ssid)["password"] }
      rescue JSON::ParserError => e
        logger.info "Invalid puavoWlanSSID value"
        return []
      end
    end
  end
end

