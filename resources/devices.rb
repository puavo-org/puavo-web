module PuavoRest
class DevicesModel < LdapModel

  ldap_attr_conversion :dn, :dn
  ldap_attr_conversion :cn, :hostname
  ldap_attr_conversion :puavoSchool, :school_dn
  ldap_attr_conversion :puavoDeviceType, :type
  ldap_attr_conversion :puavoDeviceImage, :image
  # TODO: Audio device etc...

  def ldap_base
    "ou=Devices,ou=Hosts,#{ @organisation_base }"
  end

  def by_hostname(hostname)
    LdapModel.convert filter(
      "(cn=#{ LdapModel.escape hostname })",
      self.class.ldap_attrs
    ).first
  end

end

class Devices < LdapSinatra

  auth Credentials::BootServer

  get "/v3/devices/:hostname" do
    json new_model(DevicesModel).by_hostname(params["hostname"])
  end

end
end
