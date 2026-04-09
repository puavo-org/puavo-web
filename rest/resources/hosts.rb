
module PuavoRest
class Host < LdapModel
  ldap_map :dn, :dn
  ldap_map :objectclass, :object_classes, LdapConverters::ArrayValue
  ldap_map :macaddress, :mac_address
  ldap_map :macaddress, :mac_addresses, LdapConverters::ArrayValue
  ldap_map :puavoautomaticimageupdates,
           :automatic_image_updates,
           LdapConverters::StringBoolean
  ldap_map :puavoconf, :puavoconf, LdapConverters::PuavoConfObj
  ldap_map :puavodeviceavailableimage,
           :available_images,
           LdapConverters::ArrayValue
  ldap_map :puavodevicebootimage, :preferred_boot_image
  ldap_map :puavodevicebootmode, :boot_mode
  ldap_map :puavodevicecurrentimage, :current_image, LdapConverters::SingleValue
  ldap_map :puavodevicehwinfo, :hw_info
  ldap_map :puavodeviceimage, :preferred_image
  ldap_map :puavodevicekernelarguments, :kernel_arguments
  ldap_map :puavodevicekernelversion, :kernel_version
  ldap_map :puavodevicereset, :reset, LdapConverters::JSONObj
  ldap_map :puavodevicetype, :type
  ldap_map :puavohostname, :hostname
  ldap_map :puavoid, :puavo_id
  ldap_map :puavoimageseriessourceurl,
           :image_series_source_urls,
           LdapConverters::ArrayValue
  ldap_map :puavokeyboardlayout, :keyboard_layout
  ldap_map :puavokeyboardvariant, :keyboard_variant
  ldap_map(:puavotag, :tags) { |v| Array(v) }
  ldap_map :puavotimezone, :timezone
  ldap_map :puavolocale, :locale

  ldap_map :serialnumber, :serial_number
  ldap_map :puavodevicemanufacturer, :manufacturer
  ldap_map :puavodevicemodel, :model

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
    when "bootserver"
      BootServer.by_dn!(host.dn)
    else
      Device.by_dn!(host.dn)
    end
  end

  # Cached organisation query
  def organisation
    return @organisation if @organisation
    @organisation = Organisation.by_dn(self.class.organisation["base"])
  end

  def preferred_boot_image
    preferred_image
  end

  def self.create_device_info(hostname)
    default_profiles = nil

    # handle these special names so that we return only puavoconf for
    # organisation
    if %w(diskinstaller preinstalled unregistered).include?(hostname) then
      host_object = UnregisteredDevice.new
      default_profiles = [ hostname ]
    else
      host_object = self.by_hostname!(hostname)
    end
    host = host_object.to_hash
    host.delete('hw_info')    # devices are not interested in this

    host['conf'] = host_object.generate_extended_puavo_conf

    # Merge explicit puavo-conf settings and coerce all values to strings
    # (coercing might not be necessary but above we use only strings and
    # clients do not do anything with type information, because typing should
    # not be relevant with puavo-conf).
    explicit_puavoconf = Hash[
      host_object.puavoconf.map { |k,v| [ k, v.to_s ] }
    ]
    host['conf'].merge!(explicit_puavoconf)

    puavo_conf_profiles = host['conf'].keys.select do |key|
                            key.start_with?('puavo.profile.')
                          end

    # "puavo.profiles.list" might be constructed from other settings.
    unless host['conf'].has_key?('puavo.profiles.list') then
      unless default_profiles then
        use_personal_profile \
          = (host['conf']['puavo.admin.personally_administered'] == 'true')

        default_profiles = [
          host_object.type,

          # these tags will go away, puavo.profile.X will take their place
          %w(bigtouch infotv webkiosk).select do |k|
            host_object.tags.include?(k)
          end,

          puavo_conf_profiles.map do |k|
            host['conf'][k] == 'true' ? k.sub('puavo.profile.', '') : nil
          end,

          (use_personal_profile ? 'personal' : nil),
        ].flatten.compact.uniq
      end
      host['conf']['puavo.profiles.list'] = default_profiles.join(',')
    end

    host
  end

  def generate_extended_puavo_conf
    @extended_puavoconf = {}

    extend_puavoconf('puavo.desktop.keyboard.layout',  keyboard_layout)
    extend_puavoconf('puavo.desktop.keyboard.variant', keyboard_variant)
    extend_puavoconf('puavo.image.automatic_updates',  automatic_image_updates)
    extend_puavoconf('puavo.image.preferred',          preferred_image)
    extend_puavoconf('puavo.image.series.urls',
                     image_series_source_urls,
                     lambda { |v| v.to_json })
    extend_puavoconf('puavo.kernel.arguments', kernel_arguments)
    extend_puavoconf('puavo.kernel.version',   kernel_version)
    extend_puavoconf('puavo.l10n.locale',      locale)
    extend_puavoconf('puavo.time.timezone',    timezone)

    return @extended_puavoconf
  end

  def extend_puavoconf(key, value, fn=nil)
    return if value.nil?
    newvalue = fn ? fn.call(value) : value
    return if newvalue.nil?
    @extended_puavoconf[key] = newvalue.to_s
  end

  def save_hwinfo!(sysinfo_json)
    if sysinfo_json.to_s.empty? then
      raise 'no sysinfo parameter or it is empty'
    end

    data = JSON.parse(sysinfo_json)

    # Do some basic sanity checking on the data
    unless data['timestamp'] && data['this_image'] && data['this_release']
      raise 'received data failed basic sanity checks'
    end

    # We can't assume the source device's clock is correct, but we can assume
    # the server's clock is. Replace the timestamp.
    data['timestamp'] = Time.now.to_i

    self.hw_info = data.to_json
    self.save!
  end

end
end
