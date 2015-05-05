require_relative "./hosts"
require_relative "../lib/error_codes"

module PuavoRest
class Device < Host

  ldap_map :puavoSchool, :school_dn
  ldap_map :puavoPreferredServer, :preferred_server
  ldap_map :puavoDeviceVertRefresh, :vertical_refresh
  ldap_map :puavoPrinterQueue, :printer_queue_dns, LdapConverters::ArrayValue
  ldap_map :puavoDeviceXrandr, :xrandr, LdapConverters::ArrayValue
  ldap_map :puavoDeviceXrandrDisable, :xrandr_disable, LdapConverters::StringBoolean
  ldap_map :puavoDeviceXserver, :graphics_driver
  ldap_map :puavoDefaultPrinter, :default_printer_name
  ldap_map :puavoDeviceResolution, :resolution
  ldap_map :puavoAllowGuest, :allow_guest, LdapConverters::StringBoolean
  ldap_map :puavoAutomaticImageUpdates, :automatic_image_updates, LdapConverters::StringBoolean
  ldap_map :puavoPersonallyAdministered, :personally_administered, LdapConverters::StringBoolean
  ldap_map :puavoPersonalDevice, :personal_device, LdapConverters::StringBoolean
  ldap_map :puavoPrinterDeviceURI, :printer_device_uri
  ldap_map :puavoDeviceDefaultAudioSource, :default_audio_source
  ldap_map :puavoDeviceDefaultAudioSink, :default_audio_sink
  ldap_map :puavoMountpoint, :mountpoints, LdapConverters::ArrayValue
  ldap_map :puavoTimezone, :timezone
  ldap_map :puavoKeyboardLayout, :keyboard_layout
  ldap_map :puavoKeyboardVariant, :keyboard_variant
  ldap_map :puavoDevicePrimaryUser, :primary_user_dn
  ldap_map :puavoImageSeriesSourceURL, :image_series_source_url

  ldap_map :puavoDeviceAutoPowerOffMode, :autopoweroff_mode
  ldap_map :puavoDeviceOnHour,           :daytime_start_hour
  ldap_map :puavoDeviceOffHour,          :daytime_end_hour

  def self.ldap_base
    "ou=Devices,ou=Hosts,#{ organisation["base"] }"
  end


  def self.by_hostname(hostname)
    by_attr(:hostname, hostname)
  end

  def self.by_hostname!(hostname)
    by_attr!(:hostname, hostname)
  end

  # Find device by it's mac address
  def self.by_mac_address!(mac_address)
    by_attr!(:hostname, mac_address)
  end

  def printer_ppd
    Array(self.class.raw_by_dn(self["dn"], "puavoPrinterPPD")["puavoPrinterPPD"]).first
  end

  # Cached school query
  def school
    @school ||= School.by_dn(school_dn)
  end

  def printer_queues
    @printer_queues ||= PrinterQueue.by_dn_array(printer_queue_dns)
  end

  computed_attr :preferred_language
  def preferred_language
    school.preferred_language
  end

  computed_attr :locale
  def locale
    school.locale
  end

  computed_attr :primary_user
  def primary_user
    if user_dn = get_own(:primary_user_dn)
      begin
        return User.by_dn(user_dn).username
      rescue LDAP::ResultError
        return ""
      end
    end
  end

  def preferred_image
    image = get_own(:preferred_image)

    # Always fallback to school's preferred image
    image ||= school.get_own(:preferred_image)

    # Bootserver's preferred image is used only for netboot devices
    # so that localboot devices get always consistent settings
    if !image and netboot?
      image = BootServer.current_image
    end

    # Organisation fallback
    image ||= school.organisation.preferred_image

    image.strip if image
  end

  def allow_guest
     if get_own(:allow_guest).nil?
        school.allow_guest
      else
        get_own(:allow_guest)
      end
  end

  def automatic_image_updates
     if get_own(:automatic_image_updates).nil?
        school.automatic_image_updates
      else
        get_own(:automatic_image_updates)
      end
  end

  def personal_device
     if get_own(:personal_device).nil?
       school.personal_device
     else
       get_own(:personal_device)
     end
  end

  def image_series_source_url
    if get_own(:image_series_source_url).nil?
      school.image_series_source_url
    else
      get_own(:image_series_source_url)
    end
  end

  def tags
    school.tags.concat(get_own(:tags)).uniq.sort
  end

  computed_attr :homepage
  def homepage
    school.homepage
  end

  def messages
    # TODO: merge with devices own messages
    school.messages
  end

  # Merge device's and school's mountpoints.
  # Use device's mountpoint if it is same that at school
  def mountpoints
    device_mounts = get_own(:mountpoints).map{ |m| JSON.parse(m) }
    school_mounts = school.mountpoints
    mountpoints = device_mounts.map{ |m| m["mountpoint"] }

    school_mounts.each do |mounts|
      next if mountpoints.include?(mounts["mountpoint"])

      device_mounts.push(mounts)
    end
    device_mounts
  end

  def self.search_filters
    [
      create_filter_lambda(:hostname) { |v| "*#{ v }*" },

      # Our ldap schema does not allow wildcards in the 'macAddress' field. So
      # we must match only with excact filters
      create_filter_lambda(:mac_address) { |v| v },
    ]
  end

  def timezone
    if get_own(:timezone).nil?
      school.timezone
    else
      get_own(:timezone)
    end
  end

  def keyboard_layout
    if get_own(:keyboard_layout).nil?
      school.keyboard_layout
    else
      get_own(:keyboard_layout)
    end
  end

  def keyboard_variant
    if get_own(:keyboard_variant).nil?
      school.keyboard_variant
    else
      get_own(:keyboard_variant)
    end
  end

  def autopoweroff_attr_with_school_fallback(attr)
    [ nil, 'default' ].include?( get_own(:autopoweroff_mode) ) \
      ? school.send(attr)                                      \
      : get_own(attr)
  end

  autopoweroff_attrs = [ :autopoweroff_mode,
                         :daytime_start_hour,
                         :daytime_end_hour ]
  autopoweroff_attrs.each do |attr|
    define_method(attr) { autopoweroff_attr_with_school_fallback(attr) }
  end
end

class Devices < LdapSinatra

  get "/v3/devices/_search" do
    auth :basic_auth, :kerberos
    json Device.search(params["q"])
  end

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

  post "/v3/devices/:hostname" do
    auth :basic_auth, :kerberos
    device = Device.by_hostname!(params["hostname"])
    device.update!(json_params)
    device.save!
    json device
  end



  get "/v3/devices" do
    auth :basic_auth, :server_auth, :kerberos
    json Device.all(params["attributes"])
  end

  get "/v3/devices/:hostname/feed" do

    messages = LdapModel.setup(:credentials => CONFIG["server"]) do
      Device.by_hostname!(params["hostname"]).messages
    end

    json messages
  end


  get "/v3/devices/:hostname/wireless_printer_queues" do
    auth :basic_auth, :server_auth

    device = Device.by_hostname!(params["hostname"])
    json device.school.wireless_printer_queues
  end

end
end
