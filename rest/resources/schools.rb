module PuavoRest
class SchoolsModel < LdapModel

  ldap_attr_conversion :dn, :dn
  ldap_attr_conversion :puavoDeviceImage, :image

  def by_dn(dn)
    LdapModel.convert _find_by_dn(LdapModel.escape dn)
  end

end
end
