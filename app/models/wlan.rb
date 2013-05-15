module Wlan
  attr_accessor :wlan_name, :wlan_type, :wlan_password

  def update_wlan_attributes(args)
    set_attribute( "puavoWlanSSID", "#{args[:wlan_type]}:#{args[:wlan_name]}:#{args[:wlan_password]}" )
    set_attribute( "puavoWlanChannel", args[:puavoWlanChannel] )
  end

  def wlan_name
    if wlan_ssid = get_attribute( "puavoWlanSSID" )
      wlan_ssid.split(":")[1]
    end
  end

  def wlan_type
    if wlan_ssid = get_attribute( "puavoWlanSSID" )
      wlan_ssid.split(":")[0]
    end
  end

  def wlan_password
    if wlan_ssid = get_attribute( "puavoWlanSSID" )
      wlan_ssid.split(":")[2]
    end
  end
end
