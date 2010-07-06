class LdapBase < ActiveLdap::Base
  ldap_mapping :dn_attribute => "dc",
               :prefix => ""
end
