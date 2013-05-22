module PuavoRest
class Organisations < LdapModel

  ldap_attr_conversion :puavoDeviceImage, :image

  def by_dn(dn)
    data = _find_by_dn(dn)
    LdapModel.convert data
  end

end
end
