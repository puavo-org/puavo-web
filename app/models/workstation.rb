class Workstation < ActiveLdap::Base
  ldap_mapping :dn_attribute => "cn",
               :prefix => "ou=workstations"
end
