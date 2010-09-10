class Device < LdapBase
  ldap_mapping( :dn_attribute => "puavoId",
                :prefix => "ou=Devices,ou=Hosts",
                :classes => ['top', 'device', 'puppetClient'] )


  before_validation :set_puavo_id
  before_save :set_parentNode

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

  def set_puavo_id
    self.puavoId = IdPool.next_puavo_id if attribute_names.include?("puavoId") && self.puavoId.nil?
    self.cn = self.puavoHostname
  end
  def set_parentNode
    self.parentNode = LdapOrganisation.current.puavoDomain
  end
end
