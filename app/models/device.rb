class Device < ActiveLdap::Base
  ldap_mapping( :dn_attribute => "puavoId",
                :prefix => "ou=Devices,ou=Hosts",
                :classes => ['top', 'device'] )


  before_validation :set_puavo_id

  def validate
    unless Host.validates_uniqueness_of_hostname(self.puavoHostname)
      errors.add "device[puavoHostname]", "Hostname must be unique"
    end
  end

  def self.roles
    ['puavoNetbootDevice', 'puavoLocalbootDevice', 'puavoPrinter']
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
