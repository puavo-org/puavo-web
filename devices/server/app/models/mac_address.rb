class MACAddress < LdapBase
  ldap_mapping( :dn_attribute => "dhcpHWAddress",
                :prefix => "ou=Devices,ou=Hosts",
                :classes => ['top', 'dhcpHost'] )
end
