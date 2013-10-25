require_relative "./hosts"
require_relative "../lib/error_codes"

module PuavoRest
class Device < Host

  ldap_map :dn, :dn
  ldap_map :cn, :hostname
  ldap_map :puavoSchool, :school_dn
  ldap_map :puavoDeviceType, :type
  ldap_map :puavoDeviceBootImage, :preferred_boot_image
  ldap_map :puavoDeviceImage, :preferred_image
  ldap_map :puavoPreferredServer, :preferred_server
  ldap_map :puavoDeviceKernelArguments, :kernel_arguments
  ldap_map :puavoDeviceKernelVersion, :kernel_version
  ldap_map :puavoDeviceVertRefresh, :vertical_refresh
  ldap_map(:puavoPrinterQueue, :printer_queue_dns){ |v| Array(v) }
  ldap_map :macAddress, :mac_address
  ldap_map :puavoId, :puavo_id
  ldap_map :puavoId, :puavo_id
  ldap_map :puavoDeviceBootMode, :boot_mode
  ldap_map :puavoDeviceXrandrDisable, :xrand_disable
  ldap_map :puavoDeviceXserver, :graphics_driver
  ldap_map :puavoDefaultPrinter, :default_printer_name
  ldap_map :puavoDeviceResolution, :resolution
  ldap_map :puavoAllowGuest, :allow_guest, &LdapConverters.string_boolean
  ldap_map :puavoPersonalDevice, :personal_device, &LdapConverters.string_boolean
  ldap_map :puavoPrinterDeviceURI, :printer_device_uri


  def self.ldap_base
    "ou=Devices,ou=Hosts,#{ organisation["base"] }"
  end


  # Find device by it's hostname
  def self.by_hostname(hostname)
    Array(filter("(puavoHostname=#{ escape hostname })")).first
  end

  def self.by_hostname!(hostname)
    device = by_hostname(hostname)
    if device.nil?
      raise NotFound, :user => "Cannot find device with hostname '#{ hostname }'"
    end
    device
  end

  # Find device by it's mac address
  def self.by_mac_address!(mac_address)
    device = filter("(macAddress=#{ escape mac_address })").first
    if device.nil?
      raise NotFound, :user => "Cannot find device with mac address '#{ mac address }'"
    end
    device
  end

  def printer_ppd
    Array(self.class.raw_by_dn(self["dn"], "puavoPrinterPPD")["puavoPrinterPPD"]).first
  end

  # Cached school query
  def school
    return @school if @school
    @school = School.by_dn(school_dn)
  end

  def printer_queues
    PrinterQueue.by_dn_array(printer_queue_dns)
  end

  def preferred_boot_image
    # FIXME
    super
  end

  def preferred_image
     if get_original(:preferred_image).nil?
       school.preferred_image
     else
       get_original(:preferred_image)
     end
  end

  def allow_guest
     if get_original(:allow_guest).nil?
        school.allow_guest
      else
        get_original(:allow_guest)
      end
  end

  def personal_device
     if get_original(:personal_device).nil?
       school.personal_device
     else
       get_original(:personal_device)
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
    auth :basic_auth, :server_auth, :legacy_server_auth

    device = Device.by_hostname!(params["hostname"])
    json device
  end

  get "/v3/devices/:hostname/wireless_printer_queues" do
    auth :basic_auth, :server_auth

    device = Device.by_hostname!(params["hostname"])
    json device.school.wireless_printer_queues
  end

end
end
