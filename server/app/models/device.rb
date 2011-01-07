class Device < DeviceBase
  ldap_mapping( :dn_attribute => "puavoId",
                :prefix => "ou=Devices,ou=Hosts",
                :classes => ['top', 'device', 'puppetClient'] )

  after_save :set_mac_addresses
  before_destroy :remove_mac_addresses

  def self.allowed_classes
    ['puavoNetbootDevice', 'puavoLocalbootDevice', 'puavoPrinter']
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
