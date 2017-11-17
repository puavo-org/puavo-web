module Wlan

  # Set WLAN networks as array
  #
  # @param [Array] Array of wlan networks.
  #     Each item should be a Hash with keys :ssid, :type, :wlan_ap and
  #     :password
  def wlan_networks=(data)
    set_attribute("puavoWlanSSID",
      data.map do |network|
        network.to_json
      end
   )
    data
  end

  # Get WLAN networks as array of Hashes
  #
  # @return [Array] Array of WLAN Network Hashes
  def wlan_networks
    Array(get_attribute("puavoWlanSSID")).map do |network_json|
      begin
        JSON.parse(network_json)
      rescue JSON::ParserError
        logger.info "Invalid puavoWlanSSID JSON value: #{ network_json }"
        nil
      end
    end.compact
  end

  def validate_wlan_attributes
    wlan_names = Array( get_attribute("puavoWlanSSID") ).map { |ssid| ssid.split(":")[1] }
    if wlan_names.count != wlan_names.uniq.count
      errors.add( :puavoWlanSSID, I18n.t("activeldap.errors.messages.wlan.duplicate_name") )
    end
  end

  def update_wlan_attributes(new_attrs)
    wlan_ap   = new_attrs[:wlan_ap] || {}
    max_index = new_attrs[:wlan_name].keys.count - 1

    new_wlan_networks = []

    (0..max_index).each do |index|
      next if new_attrs[:wlan_name][index.to_s].empty?
      if wlan_ap.has_key?(index.to_s)
        wlan_ap_status = wlan_ap[index.to_s] == "enabled" ? true : false
      end

      new_wlan_networks.push(:ssid     => new_attrs[:wlan_name][index.to_s],
                             :type     => new_attrs[:wlan_type][index.to_s],
                             :wlan_ap  => wlan_ap_status,
                             :password => new_attrs[:wlan_password][index.to_s])
    end

    self.wlan_networks = new_wlan_networks
  end

  def wlan_name
    wlan_networks.map { |w| w["ssid"] }
  end

  def wlan_type
    wlan_networks.map { |w| w["type"] }
  end

  def wlan_password
    wlan_networks.map { |w| w["password"] }
  end

  def wlan_ap
    wlan_networks.map { |w| w["wlan_ap"] }
  end
end

