module PuavoRest
class School < LdapHash
  ldap_map :dn, :dn
  ldap_map :puavoDeviceImage, :preferred_image
end
end
