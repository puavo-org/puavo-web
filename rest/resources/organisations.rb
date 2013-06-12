module PuavoRest
class Organisation < LdapHash
  ldap_map :puavoDeviceImage, :preferred_image
end
end
