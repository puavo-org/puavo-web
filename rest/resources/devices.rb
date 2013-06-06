module PuavoRest
class DevicesModel < LdapModel

  ldap_attr_conversion :dn, :dn
  ldap_attr_conversion :cn, :hostname
  ldap_attr_conversion :puavoSchool, :school
  ldap_attr_conversion :puavoDeviceType, :type
  ldap_attr_conversion :puavoDeviceImage, :preferred_image
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
  def by_hostname(hostname, fallback_defaults=false)
    device = DevicesModel.convert filter(
      "(cn=#{ LdapModel.escape hostname })",
      self.class.ldap_attrs
    ).first

    if fallback_defaults && device["preferred_image"].nil?
      school = SchoolsModel.
        new(@ldap_conn, @organisation_info).
        by_dn(device["school"])
      device["preferred_image"] = school["preferred_image"]
    end

    if device.nil?
      raise BadInput, "Cannot find device with hostname '#{ hostname }'"
    else
      device
    end
  end

end

class Devices < LdapSinatra

  auth Credentials::BootServer

  # Get detailed information about the server by hostname
  #
  # Example:
  #
  #    GET /v3/devices/testthin
  #
  #    {
  #      "kernel_arguments": "lol",
  #      "kernel_version": "0.1",
  #      "vertical_refresh": "2",
  #      "resolution": "320x240",
  #      "graphics_driver": "nvidia",
  #      "image": "myimage",
  #      "dn": "puavoId=10,ou=Devices,ou=Hosts,dc=edu,dc=hogwarts,dc=fi",
  #      "puavo_id": "10",
  #      "mac_address": "08:00:27:88:0c:a6",
  #      "type": "thinclient",
  #      "school": "puavoId=1,ou=Groups,dc=edu,dc=hogwarts,dc=fi",
  #      "hostname": "testthin",
  #      "boot_mode": "netboot",
  #      "xrand_disable": "FALSE"
  #    }
  #
  #
  # @!macro route
  get "/v3/devices/:hostname" do
    d = new_model(DevicesModel).by_hostname(
      params["hostname"],
      !!params["fallback_defaults"]
    )

    if d
      json d
    else
      not_found "Cannot find device by hostname #{ params["hostname"] }"
    end
  end

end
end
