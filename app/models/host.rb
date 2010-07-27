class Host < LdapBase
  ldap_mapping( :dn_attribute => "puavoId",
                :prefix => "ou=Hosts",
                :classes => ['top', 'device'] )

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
end
