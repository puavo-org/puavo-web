module PuavoRest
class SchoolsModel < LdapModel

  ldap_attr_conversion :dn, :dn
  ldap_attr_conversion :puavoDeviceImage, :image

  def by_dn(dn)
    SchoolsModel.convert _find_by_dn(SchoolsModel.escape dn)
  end

end
end
