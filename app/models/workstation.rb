class Workstation < ActiveLdap::Base
  ldap_mapping( :dn_attribute => "cn",
                :prefix => "ou=Hosts",
                :classes => ['top', 'device', 'ipHost', 'puppetClient'] )
end
