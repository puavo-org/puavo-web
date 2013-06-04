module PuavoRest
class DevicesModel < LdapModel

  ldap_attr_conversion :dn, :dn
  ldap_attr_conversion :cn, :hostname
  ldap_attr_conversion :puavoSchool, :school
  ldap_attr_conversion :puavoDeviceType, :type
  ldap_attr_conversion :puavoDeviceImage, :image
  ldap_attr_conversion :puavoPreferredServer, :preferred_server
  ldap_attr_conversion :puavoDeviceKernelArguments, :kernel_arguments
  ldap_attr_conversion :puavoDeviceKernelVersion, :kernel_version
  ldap_attr_conversion :puavoDeviceVertRefresh, :vertical_refresh
  ldap_attr_conversion :macAddress, :mac_address
  ldap_attr_conversion :puavoId, :puavo_id
  ldap_attr_conversion :puavoId, :puavo_id
  ldap_attr_conversion :puavoDeviceBootMode, :boot_mode
  ldap_attr_conversion :puavoDeviceXrandrDisable, :xrand_disable
  ldap_attr_conversion :puavoDeviceXserver, :graphics_driver
  ldap_attr_conversion :puavoDeviceResolution, :resolution

  def ldap_base
    "ou=Devices,ou=Hosts,#{ @organisation_info["base"] }"
  end

  # Find device by it's hostname
  def by_hostname(hostname)
    data = filter(
      "(cn=#{ LdapModel.escape hostname })",
      self.class.ldap_attrs
    )

    if data.first.nil?
      raise BadInput, "Cannot find device with hostname '#{ hostname }'"
    else
      DevicesModel.convert data.first
    end
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
