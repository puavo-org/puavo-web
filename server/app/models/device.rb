class Device < DeviceBase
  ldap_mapping( :dn_attribute => "puavoId",
                :prefix => "ou=Devices,ou=Hosts",
                :classes => ['top', 'device', 'puppetClient'] )

#  after_save :set_mac_addresses
  before_destroy :remove_mac_addresses

  def self.allowed_classes
    ['puavoNetbootDevice', 'puavoLocalbootDevice', 'puavoPrinter', 'cupsPrinter']
  end

  def objectClass_by_device_type=(device_type)
    self.add_class( Host.objectClass_by_device_type(device_type) )
  end

  def id
    self.puavoId.to_s if attribute_names.include?("puavoId") && !self.puavoId.nil?
  end

  def classes=(*args)
    args += ['top', 'device', 'puppetClient']
    super(args)
  end

  # Building hash for to_json method with better name of attributes
  #  * data argument may be Device or Hash
  def self.build_hash_for_to_json(data)
    new_device_hash = {}
    # Note: value of attribute may be raw ldap value eg. { puavoHostname => ["thinclient-01"] }
    device_attributes = [
       { :original_attribute_name => "description",
         :new_attribute_name => "description",
         :value_block => lambda{ |value| Array(value).first } },
       { :original_attribute_name => "ipHostNumber",
         :new_attribute_name => "ip_address",
         :value_block => lambda{ |value| Array(value).first } },
       { :original_attribute_name => "jpegPhoto",
         :new_attribute_name => "image",
         :value_block => lambda{ |value| Array(value).first } },
       { :original_attribute_name => "macAddress",
         :new_attribute_name => "mac_address",
         :value_block => lambda{ |value| Array(value).first } },
       { :original_attribute_name => "puavoDefaultPrinter",
         :new_attribute_name => "default_printer",
         :value_block => lambda{ |value| Array(value).first } },
       { :original_attribute_name => "puavoDeviceAutoPowerOffMode",
         :new_attribute_name => "auto_power_mode",
         :value_block => lambda{ |value| Array(value).first } },
       { :original_attribute_name => "puavoDeviceBootMode",
         :new_attribute_name => "boot_mode",
         :value_block => lambda{ |value| Array(value).first } },
       { :original_attribute_name => "puavoDeviceManufacturer",
         :new_attribute_name => "manufacturer",
         :value_block => lambda{ |value| Array(value).first } },
       { :original_attribute_name => "puavoDeviceModel",
         :new_attribute_name => "model",
         :value_block => lambda{ |value| Array(value).first } },
       { :original_attribute_name => "puavoLatitude",
         :new_attribute_name => "latitude",
         :value_block => lambda{ |value| Array(value).first } },
       { :original_attribute_name => "puavoLocationName",
         :new_attribute_name => "location_name",
         :value_block => lambda{ |value| Array(value).first } },
       { :original_attribute_name => "puavoLongitude",
         :new_attribute_name => "longitude",
         :value_block => lambda{ |value| Array(value).first } },
       { :original_attribute_name => "puavoPurchaseDate",
         :new_attribute_name => "purchase_date",
         :value_block => lambda{ |value| Array(value).first } },
       { :original_attribute_name => "puavoPurchaseLocation",
         :new_attribute_name => "purchase_location",
         :value_block => lambda{ |value| Array(value).first } },
       { :original_attribute_name => "puavoPurchaseURL",
         :new_attribute_name => "purchase_url",
         :value_block => lambda{ |value| Array(value).first } },
       { :original_attribute_name => "puavoSupportContract",
         :new_attribute_name => "support_contract",
         :value_block => lambda{ |value| Array(value).first } },
       { :original_attribute_name => "puavoTag",
         :new_attribute_name => "tags",
         :value_block => lambda{ |value| Array(value).first } },
       { :original_attribute_name => "puavoWarrantyEndDate",
         :new_attribute_name => "warranty_end_date",
         :value_block => lambda{ |value| Array(value).first } },
       { :original_attribute_name => "serialNumber",
         :new_attribute_name => "serialnumber",
         :value_block => lambda{ |value| Array(value).first } },
       { :original_attribute_name => "puavoHostname",
         :new_attribute_name => "hostname",
         :value_block => lambda{ |value| Array(value).first } },
       { :original_attribute_name => "puavoSchool",
         :new_attribute_name => "school_id",
         :value_block => lambda{ |value| value.to_s.match(/puavoId=([^, ]+)/)[1].to_i } } ]

    device_attributes.each do |attr|
      attribute_value = data.class == Hash ? data[attr[:original_attribute_name]] : data.send(attr[:original_attribute_name])
      new_device_hash[attr[:new_attribute_name]] = attr[:value_block].call(attribute_value)
    end
    return new_device_hash
  end

  private

  # Create MACAddress object for each device's macAddress etry
  # dhcpHWAddress == "ethernet <HWaddress>"
  # cn == device.puavoHostname
  def set_mac_addresses
    exists_mac_addresses = MACAddress.all(:prefix => "puavoId=#{self.puavoId}")
    # Example of dhcpHWAddress: ethernet 00:11:22:33:44:55
    removed_mac_addresses = exists_mac_addresses.map{ |m| m.dhcpHWAddress[/[^ ]+$/] } - Array(self.macAddress)
    added_mac_addresses = Array(self.macAddress) - exists_mac_addresses.map{ |m| m.dhcpHWAddress[/[^ ]+$/] }


    exists_mac_addresses.each do |mac_address|
      if removed_mac_addresses.include?(mac_address.dhcpHWAddress[/[^ ]+$/])
        mac_address.destroy
      else
        if mac_address.cn != self.puavoHostname
          mac_address.cn = puavoHostname
          mac_address.save!
        end
      end
    end

    added_mac_addresses.each do |mac|
      new_mac_address = MACAddress.new("dhcpHWAddress=ethernet #{mac},#{self.dn.to_s}")
      new_mac_address.cn = self.puavoHostname
      new_mac_address.save!
    end
  end

  # Remove MACAddress objects before destroy
  def remove_mac_addresses
    MACAddress.all(:prefix => "puavoId=#{self.puavoId}").each do |mac_address|
      mac_address.destroy
    end
  end
end
