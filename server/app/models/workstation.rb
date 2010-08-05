class Workstation < DeviceBase
  ldap_mapping( :dn_attribute => "puavoId",
                :prefix => "ou=Hosts",
                :classes => ['top', 'device', 'ipHost', 'puavoWorkstation'] )

end
