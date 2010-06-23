class Server < ActiveLdap::Base
  ldap_mapping :dn_attribute => "cn",
               :prefix => "ou=servers"
end
