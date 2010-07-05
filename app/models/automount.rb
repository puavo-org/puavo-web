class Automount < ActiveLdap::Base
  ldap_mapping( :dn_attribute => "puavoId",
                :prefix => "ou=auto.master,ou=Automount",
                :classes => ['top', 'automount', 'puavoShare'] )
end
