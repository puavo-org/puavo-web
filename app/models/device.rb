class Device < LdapBase
  ldap_mapping( :dn_attribute => "puavoId",
                :prefix => "ou=Devices,ou=Hosts",
                :classes => ['top', 'device', 'puppetClient'] )
  
  def id
    self.puavoId.to_s if attribute_names.include?("puavoId") && !self.puavoId.nil?
  end
end
