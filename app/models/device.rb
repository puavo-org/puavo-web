# frozen_string_literal: true

class Device < DeviceBase
  include Puavo::Client::HashMixin::Device
  include HasPrinterMixin

  ldap_mapping dn_attribute: 'puavoId',
               prefix: 'ou=Devices,ou=Hosts',
               classes: %w[top device puppetClient]

  before_destroy :remove_mac_addresses
  before_validation :read_ppd_data

  def school_id
    ActiveLdap::DistinguishedName.parse(self.puavoSchool).rdns.first['puavoId'] if self.puavoSchool
  end

  def read_ppd_data
    return unless self.puavoPrinterPPD.instance_of?(ActionDispatch::Http::UploadedFile)

    self.puavoPrinterPPD = File.binread(self.puavoPrinterPPD.path)
  end

  def self.allowed_classes
    %w[puavoNetbootDevice puavoLocalbootDevice puavoPrinter cupsPrinter]
  end

  def objectClass_by_device_type=(device_type)
    self.add_class(Host.objectClass_by_device_type(device_type))
  end

  def id
    self.puavoId.to_s if attribute_names.include?('puavoId') && !self.puavoId.nil?
  end

  def classes=(*args)
    # TODO: This can potentially duplicate the classes. Needs to be investigated.
    args += %w[top device puppetClient]
    super(args)
  end

  def self.json_attributes
    # NOTE: The attribute value may be a raw LDAP value (eg. { puavoHostname => ["laptop-01"] })
    DeviceBase.json_attributes.push(
      {
        original_attribute_name: 'puavoSchool',
        new_attribute_name: 'school_id',
        value_block: lambda { |value| value.to_s.match(/puavoId=([^, ]+)/)[1].to_i }
      }
    )
  end

  def puavoPersonallyAdministered=(boolean)
    value = fix_boolean_value(boolean)
    set_attribute('puavoPersonallyAdministered', value)
  end

  private

  # Convert the macAddress array into an array of MacAddress objects
  # dhcpHWAddress == "ethernet <HWaddress>"
  # cn == device.puavoHostname
  def set_mac_addresses
    exists_mac_addresses = MacAddress.all(prefix: "puavoId=#{self.puavoId}")

    # An example of a dhcpHWAddress: ethernet 00:11:22:33:44:55
    removed_mac_addresses = exists_mac_addresses.map { |m| m.dhcpHWAddress[/[^ ]+$/] } - Array(self.macAddress)
    added_mac_addresses = Array(self.macAddress) - exists_mac_addresses.map { |m| m.dhcpHWAddress[/[^ ]+$/] }

    exists_mac_addresses.each do |mac_address|
      if removed_mac_addresses.include?(mac_address.dhcpHWAddress[/[^ ]+$/])
        mac_address.destroy
      elsif mac_address.cn != self.puavoHostname
        mac_address.cn = puavoHostname
        mac_address.save!
      end
    end

    added_mac_addresses.each do |mac|
      new_mac_address = MacAddress.new("dhcpHWAddress=ethernet #{mac},#{self.dn.to_s}")
      new_mac_address.cn = self.puavoHostname
      new_mac_address.save!
    end
  end

  # Remove MacAddress objects before destroy
  def remove_mac_addresses
    MacAddress.all(prefix: "puavoId=#{self.puavoId}").map(&:destroy)
  end
end
