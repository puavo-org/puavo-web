require_relative "../lib/error_codes"

module PuavoRest
class Host < LdapModel

  ldap_map :dn, :dn
  ldap_map :puavoDeviceType, :type
  ldap_map :macAddress, :mac_address
  ldap_map :puavoId, :puavo_id


  def self.ldap_base
    "ou=Hosts,#{ organisation["base"] }"
  end

  # Find host by it's mac address
  def self.by_mac_address(mac_address)
    host = filter("(macAddress=#{ escape mac_address })").first
    if host.nil?
      raise NotFound, :user => "Cannot find host with mac address '#{ mac_address }'"
    end
    host
  end

  # Cached organisation query
  def organisation
    return @organisation if @organisation
    @organisation = Organisation.by_dn(self.class.organisation["base"])
  end

  def preferred_boot_image
    if get_original(:preferred_boot_image).nil?
      preferred_image
    else
      get_original(:preferred_boot_image)
    end
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
  append ro initrd=ltsp/#{preferred_boot_image}/initrd.img#{grub_kernel_version} init=/sbin/init-puavo puavo.hosttype=#{grub_type} root=/dev/nbd0 nbdroot=:#{preferred_boot_image} #{kernel_arguments}
  ipappend 2
EOF
  end

end
end
