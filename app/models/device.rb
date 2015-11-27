class Device < DeviceBase
  include Puavo::Client::HashMixin::Device
  include HasPrinterMixin

  ldap_mapping( :dn_attribute => "puavoId",
                :prefix => "ou=Devices,ou=Hosts",
                :classes => ['top', 'device', 'puppetClient'] )

#  after_save :set_mac_addresses
  before_destroy :remove_mac_addresses
  before_validation :read_ppd_data

  def school_id
    if self.puavoSchool
      ActiveLdap::DistinguishedName.parse(self.puavoSchool).rdns.first["puavoId"]
    end
  end

  def read_ppd_data
    if self.puavoPrinterPPD.class == ActionDispatch::Http::UploadedFile
      data = File.open(self.puavoPrinterPPD.path, "rb").read.to_blob
      self.puavoPrinterPPD = data
    end
  end

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

  def self.json_attributes
    # Note: value of attribute may be raw ldap value eg. { puavoHostname => ["thinclient-01"] }
    DeviceBase.json_attributes.push( { :original_attribute_name => "puavoSchool",
                                       :new_attribute_name => "school_id",
                                       :value_block => lambda{ |value| value.to_s.match(/puavoId=([^, ]+)/)[1].to_i } } )
end

  def puavoPersonallyAdministered=(boolean)
    value = fix_boolean_value(boolean)
    set_attribute("puavoPersonallyAdministered", value)
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
