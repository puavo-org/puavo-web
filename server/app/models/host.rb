class Host < DeviceBase
  ldap_mapping( :dn_attribute => "puavoId",
                :prefix => "ou=Hosts",
                :classes => ['top', 'device'] )

  # Generate new Hash by configuration. Key: Host type, value: list of the object classes
  # Example:
  # { "thinclient" => "puavoNetbootDevice" }
  @@objectClass_by_device_type = PUAVO_CONFIG['device_types'].inject({}) do |result, type|
    result[type.first] = type.last["classes"]
    result
  end

  def id
    self.puavoId.to_s unless self.puavoId.nil?
  end

  def self.all
    Server.all + Device.all
  end

  def self.validates_uniqueness_of_hostname(new_host)
    if host =  Host.find(:first, :attribute => 'puavoHostname', :value => new_host.puavoHostname)
      if host.puavoId != new_host.puavoId
        return false
      end
    end
    true
  end

  def self.objectClass_by_device_type(device_type)
    @@objectClass_by_device_type[device_type]
  end

  def self.types(boottype)
    # Create deep copy of any device_types configuration.
    type_list = Marshal.load( Marshal.dump(PUAVO_CONFIG['device_types']) )

    # Filter device_type by params[:boottype]
    case boottype
    when "net"
      type_list = type_list.delete_if{ |type, value| !Array(value["classes"]).include?("puavoNetbootDevice") }
    when "local"
      type_list = type_list.delete_if{ |type, value| !Array(value["classes"]).include?("puavoLocalbootDevice") }
    when "nothing"
      type_list = type_list.delete_if do |type, value|
        Array(value["classes"]).include?("puavoLocalbootDevice") ||
          Array(value["classes"]).include?("puavoNetbootDevice")
      end
    end

    # Set host's label by user's locale. Localization values must be set on the puavo.yml
    type_list.each_key do |type|
      type_list[type]["label"] = type_list[type]["label"][I18n.locale.to_s]
    end
    
    # Set default device type by last device
    if Puavo::Authorization.current_user
      if device = Device.find( :all,
                               :attributes => ["*", "+"],
                               :attribute => 'creatorsName',
                               :value => Puavo::Authorization.current_user.dn.to_s ).max do |a,b|
          a.puavoId.to_i <=> b.puavoId.to_i
        end
        default_device_type = device.puavoDeviceType
      end
    end
    
    unless type_list.keys.include?(default_device_type)
      default_device_type = type_list.keys.first
    end

    { "default" => default_device_type,
      "label" => I18n.t("host.types.register_label"),
      "title" => I18n.t("host.types.register_title"),
      "question" => I18n.t("host.types.register_question"),
      "list" => type_list }
  end
end
