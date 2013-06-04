module PuavoRest
class DevicesModel < LdapModel

  ldap_attr_conversion :dn, :dn
  ldap_attr_conversion :cn, :hostname
  ldap_attr_conversion :puavoSchool, :school_dn
  ldap_attr_conversion :puavoDeviceType, :type
  ldap_attr_conversion :puavoDeviceImage, :image
  ldap_attr_conversion :puavoPreferredServer, :preferred_server
  # TODO: Audio device etc...

  def ldap_base
    "ou=Devices,ou=Hosts,#{ @organisation_info["base"] }"
  end

  # Find device by it's hostname
  def by_hostname(hostname)
    data = filter(
      "(cn=#{ LdapModel.escape hostname })",
      self.class.ldap_attrs
    )
    LdapModel.convert data.first
  end

end

class Devices < LdapSinatra

  auth Credentials::BootServer

  get "/v3/devices/:hostname" do
    d = new_model(DevicesModel).by_hostname(params["hostname"])
    if d
      json d
    else
      not_found "Cannot find device by hostname #{ params["hostname"] }"
    end
  end

end
end
