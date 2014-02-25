require_relative "../lib/error_codes"

module PuavoRest
class Host < LdapModel
  include LocalStore

  ldap_map :dn, :dn
  ldap_map :puavoDeviceType, :type
  ldap_map :macAddress, :mac_address
  ldap_map :puavoId, :puavo_id
  ldap_map :puavoHostname, :hostname
  ldap_map :puavoDeviceBootImage, :preferred_boot_image
  ldap_map :puavoDeviceImage, :preferred_image
  ldap_map :puavoDeviceKernelArguments, :kernel_arguments
  ldap_map :puavoDeviceBootMode, :boot_mode
  ldap_map :puavoDeviceKernelVersion, :kernel_version
  ldap_map(:puavoTag, :tags){ |v| Array(v) }


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
    if host.type == "ltspserver"
      LtspServer.by_dn!(host.dn)
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

  def grub_kernel_version
    if kernel_version.to_s.empty?
      return ""
    end
    "-" + kernel_version.to_s
  end

  def grub_type
    if type.to_s.empty?
      return "unregistered"
    end
    type.to_s
  end

  def grub_kernel_arguments
    if ["unregistered", "laptop"].include?(grub_type)
      return ""
    end

    retval = "quiet splash"
    if get_own(:kernel_arguments)
      retval = kernel_arguments
    end

    if ["thinclient", "fatclient"].include?(grub_type)
      retval += " usbcore.autosuspend=-1"
    end

    return retval
  end

  def grub_boot_configuration
    grub_header + grub_configuration
  end

  def grub_header
    if boot_mode == "dualboot"
      header =<<EOF
default menu.c32
menu title Choose a system
prompt 0
timeout 100

label local
  menu label Local OS
  localboot 0
EOF
    else
      header =<<EOF
default ltsp-NBD
ontimeout ltsp-NBD

EOF
    end
  end

  def grub_configuration
    return <<EOF

label ltsp-NBD
  menu label LTSP, using NBD
  menu default
  kernel ltsp/#{preferred_boot_image}/vmlinuz#{grub_kernel_version}
  append ro initrd=ltsp/#{preferred_boot_image}/initrd.img#{grub_kernel_version} init=/sbin/init-puavo puavo.hosttype=#{grub_type} root=/dev/nbd0 nbdroot=:#{preferred_boot_image} #{grub_kernel_arguments}
  ipappend 2
EOF
  end

end
end
