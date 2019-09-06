require 'base64'

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

  def get_certificates(new_attrs, index)
    # Try reading uploaded certificates, but if that fails (maybe no
    # certificate is sent), use the old ones if those exist.

    # Rails 4 did not care about unsafe parameters on WLAN forms, but Rails 5 does.
    # Unfortunately, it's a nightmare to construct the required require/permit chains
    # for these forms as they're fairly complex. I spent two hours on it, then gave
    # up and just use this:
    new_attrs = new_attrs.to_unsafe_h
    # If you want to complain, come up with a compact require/permit chain first,
    # then we'll talk.

    {
      :wlan_ca_cert     => read_cert(new_attrs[:wlan_ca_cert], index) \
                             || wlan_ca_cert[index],
      :wlan_client_cert => read_cert(new_attrs[:wlan_client_cert], index) \
                             || wlan_client_cert[index],
      :wlan_client_key  => read_cert(new_attrs[:wlan_client_key], index) \
                             || wlan_client_key[index],
    }
  end

  def read_cert(certhash, index)
    return nil unless certhash.kind_of?(Hash)
    return nil unless certhash.has_key?(index.to_s)
    return nil unless certhash[index.to_s].respond_to?(:tempfile)

    Base64.encode64(certhash[index.to_s].tempfile.read)
  end

  def update_wlan_attributes(new_attrs)
    new_wlan_ap = new_attrs[:wlan_ap] || {}
    max_index = new_attrs[:wlan_name].keys.count - 1

    new_wlan_networks = []

    (0..max_index).each do |index|
      index_s = index.to_s
      next if new_attrs[:wlan_name][index_s].empty?

      certs = get_certificates(new_attrs, index)

      new_wlan_type = new_attrs[:wlan_type][index_s]

      wlaninfo = {
        :ssid    => new_attrs[:wlan_name][index_s],
        :type    => new_attrs[:wlan_type][index_s],
        :wlan_ap => %w(open psk).include?(new_wlan_type) \
                      && (new_wlan_ap[index_s] == 'enabled'),
      }

      case new_attrs[:wlan_type][index_s]
        when 'eap-tls'
          wlaninfo[:certs] = {
            :ca_cert             => certs[:wlan_ca_cert],     # can be nil
            :client_cert         => certs[:wlan_client_cert], # can be nil
            :client_key          => certs[:wlan_client_key],  # can be nil
            :client_key_password => \
              new_attrs[:wlan_client_key_password][index_s]
          }
          wlaninfo[:identity] = new_attrs[:wlan_identity][index_s]
        when 'psk'
          wlaninfo[:password] = new_attrs[:wlan_password][index_s]
      end

      new_wlan_networks.push(wlaninfo)
    end

    self.wlan_networks = new_wlan_networks
  end

  def wlan_attrs(key, subkey=nil)
    if subkey then
      return wlan_networks.map { |w| w[key] ? w[key][subkey] : nil }
    end

    wlan_networks.map { |w| w[key] }
  end

  def wlan_ap;                  wlan_attrs('wlan_ap');             end
  def wlan_identity;            wlan_attrs('identity');            end
  def wlan_name;                wlan_attrs('ssid');                end
  def wlan_password;            wlan_attrs('password');            end
  def wlan_type;                wlan_attrs('type');                end

  def wlan_ca_cert;             wlan_attrs('certs', 'ca_cert'            ); end
  def wlan_client_cert;         wlan_attrs('certs', 'client_cert'        ); end
  def wlan_client_key;          wlan_attrs('certs', 'client_key'         ); end
  def wlan_client_key_password; wlan_attrs('certs', 'client_key_password'); end
end
