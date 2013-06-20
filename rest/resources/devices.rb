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
  ldap_map :puavoAllowGuest, :allow_guest, &LdapConverters.string_boolean
  ldap_map :puavoPersonalDevice, :personal_device, &LdapConverters.string_boolean
  ldap_map :puavoPrinterDeviceURI, :printer_device_uri

  FALLBACK_KEYS = [
    "preferred_image",
    "allow_guest",
    "personal_device"
  ]

  def self.ldap_base
    "ou=Devices,ou=Hosts,#{ organisation["base"] }"
  end


  # Find device by it's hostname
  def self.by_hostname(hostname)
    device = filter("(puavoHostname=#{ escape hostname })").first
    if device.nil?
      raise NotFound, :user => "Cannot find device with hostname '#{ hostname }'"
    end
    device
  end

  def printer_ppd
    Array(self.class.raw_by_dn(self["dn"], "puavoPrinterPPD")["puavoPrinterPPD"]).first
  end

  # Cached school query
  def school
    return @school if @school
    @school = School.by_dn(self["school"])
  end

  # Cached organisation query
  def organisation
    return @organisation if @organisation
    @organisation = Organisation.by_dn(self.class.organisation["base"])
  end

  # Find fallbacks from school and organisation for given keys if their values
  # are nil
  def fallback_defaults(keys=FALLBACK_KEYS)
    keys.each do |key|
      next if not self[key].nil?
      self[key] = school[key]
      next if not self[key].nil?
      self[key] = organisation[key]
    end
  end

end

class Devices < LdapSinatra

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
    auth :boot_server

    device = Device.by_hostname(params["hostname"])
    device.fallback_defaults
    json device
  end

end
end
