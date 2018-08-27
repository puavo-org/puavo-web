
module PuavoRest
class Host < LdapModel
  include LocalStore

  ldap_map :dn, :dn
  ldap_map :objectClass, :object_classes, LdapConverters::ArrayValue
  ldap_map :puavoDeviceType, :type
  ldap_map :macAddress, :mac_address
  ldap_map :macAddress, :mac_addresses, LdapConverters::ArrayValue
  ldap_map :puavoId, :puavo_id
  ldap_map :puavoHostname, :hostname
  ldap_map :puavoDeviceBootImage, :preferred_boot_image
  ldap_map :puavoDeviceImage, :preferred_image
  ldap_map :puavoDeviceKernelArguments, :kernel_arguments
  ldap_map :puavoDeviceBootMode, :boot_mode
  ldap_map :puavoDeviceKernelVersion, :kernel_version
  ldap_map(:puavoTag, :tags){ |v| Array(v) }
  ldap_map :puavoConf, :puavoconf, LdapConverters::PuavoConfObj
  ldap_map :puavoDeviceCurrentImage, :current_image, LdapConverters::SingleValue
  ldap_map :puavoDeviceAvailableImage, :available_images, LdapConverters::ArrayValue


  def netboot?
    object_classes.include?("puavoNetbootDevice")
  end

  def localboot?
    object_classes.include?("puavoLocalbootDevice")
  end

  def server?
    object_classes.include?("puavoServer")
  end

  def self.ldap_base
    "ou=Hosts,#{ organisation["base"] }"
  end

  def self.by_mac_address!(mac_address)
    host = by_attr!(:mac_address, mac_address)
    specialized_instance!(host)
  end

  def self.by_hostname!(hostname)
    host = by_attr!(:hostname, hostname)
    specialized_instance!(host)
  end

  def self.specialized_instance!(host)
    case host.type
    when "ltspserver"
      LtspServer.by_dn!(host.dn)
    when "bootserver"
      BootServer.by_dn!(host.dn)
    else
      Device.by_dn!(host.dn)
    end
  end

  def instance_key
    "host:" + hostname
  end

  def save_boot_time
    local_store_set("boottime", Time.now.to_i)

    # Expire boottime log after 1h. If boot takes longer than this we can
    # assume has been failed for some reason.
    local_store_expire("boottime", 60 * 60)
  end

  def boot_duration
    t = local_store_get("boottime")
    Time.now.to_i - t.to_i if t
  end

  # Cached organisation query
  def organisation
    return @organisation if @organisation
    @organisation = Organisation.by_dn(self.class.organisation["base"])
  end

  def preferred_image
    raise "not implemented"
  end

  def preferred_boot_image
    # preferred_boot_image is only used for thinclients. In fatclients and ltsp
    # servers the boot image is always the same as the main image
    if type == "thinclient" && get_own(:preferred_boot_image)
      return get_own(:preferred_boot_image)
    end

    preferred_image
  end
end
end
