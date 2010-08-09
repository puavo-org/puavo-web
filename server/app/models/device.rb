class Device < LdapBase
  ldap_mapping( :dn_attribute => "puavoId",
                :prefix => "ou=Devices,ou=Hosts",
                :classes => ['top', 'device'] )


  before_validation :set_puavo_id

  def validate_on_create
    unless Host.validates_uniqueness_of_hostname(self.puavoHostname)
      # FIXME: localization
      errors.add "puavoHostname", "Hostname must be unique"
    end
  end

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
    args += ['top', 'device']
    super(args)
  end

  private

  def set_puavo_id
    self.puavoId = IdPool.next_puavo_id if attribute_names.include?("puavoId") && self.puavoId.nil?
    self.cn = self.puavoHostname
  end
end
