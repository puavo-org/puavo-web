class Server < DeviceBase
  ldap_mapping( :dn_attribute => "puavoId",
                :prefix => "ou=Hosts",
                :classes => ['top', 'device', 'ipHost', 'puppetClient', 'puavoServer'] )

  has_many( :automounts, :class_name => 'Automount',
            :primary_key => 'dn',
            :foreign_key => 'puavoServer' )

  def full_hostname
    "#{self.cn}.#{LdapBase.first.puavoDomain}"
  end
end
