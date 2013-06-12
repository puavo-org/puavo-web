module PuavoRest
class Device < LdapHash

  ldap_map :dn, :dn
  ldap_map :cn, :hostname
  ldap_map :puavoSchool, :school
  ldap_map :puavoDeviceType, :type
  ldap_map :puavoDeviceImage, :preferred_image
  ldap_map :puavoPreferredServer, :preferred_server
  ldap_map :puavoDeviceKernelArguments, :kernel_arguments
  ldap_map :puavoDeviceKernelVersion, :kernel_version
  ldap_map :puavoDeviceVertRefresh, :vertical_refresh
  ldap_map :macAddress, :mac_address
  ldap_map :puavoId, :puavo_id
  ldap_map :puavoId, :puavo_id
  ldap_map :puavoDeviceBootMode, :boot_mode
  ldap_map :puavoDeviceXrandrDisable, :xrand_disable
  ldap_map :puavoDeviceXserver, :graphics_driver
  ldap_map :puavoDeviceResolution, :resolution

  def self.ldap_base
    "ou=Devices,ou=Hosts,#{ organisation["base"] }"
  end


  # Find device by it's hostname
  def self.by_hostname(hostname, fallback_defaults=false)
    device = filter("(puavoHostname=#{ escape hostname })").first

    if fallback_defaults && device["preferred_image"].nil?
      school = School.by_dn(device["school"])
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
    d = Device.by_hostname(
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
