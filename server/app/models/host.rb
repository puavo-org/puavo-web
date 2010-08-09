class Host < LdapBase
  ldap_mapping( :dn_attribute => "puavoId",
                :prefix => "ou=Hosts",
                :classes => ['top', 'device'] )

  @@objectClass_by_device_type = { "thinclient" => ["puavoNetbootDevice"],
    "fatclient" => ["puavoNetbootDevice"],
    "laptop" => ["puavoLocalbootDevice"],
    "workstation" => ["puavoLocalbootDevice"],
    "server" => ["puavoLocalbootDevice"],
    "netstand" => ["puavoLocalbootDevice"],
    "infotv" => ["puavoLocalbootDevice"] }

  def id
    self.puavoId.to_s unless self.puavoId.nil?
  end

  def self.all
    Server.all + Device.all
  end

  def self.validates_uniqueness_of_hostname(hostname)
    Host.find(:first, :attribute => 'puavoHostname', :value => hostname) ?
    false : true
  end

  def self.objectClass_by_device_type(device_type)
    @@objectClass_by_device_type[device_type]
  end
end
