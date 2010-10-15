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

  def self.validates_uniqueness_of_hostname(hostname)
    Host.find(:first, :attribute => 'puavoHostname', :value => hostname) ?
    false : true
  end

  def self.objectClass_by_device_type(device_type)
    @@objectClass_by_device_type[device_type]
  end

  def self.types
    # Create deep copy of any device_types configuration.
    type_list = Marshal.load( Marshal.dump(PUAVO_CONFIG['device_types']) )

    # Set host's label by user's locale. Localization values must be set on the puavo.yml
    type_list.each_key do |type|
      type_list[type]["label"] = type_list[type]["label"][I18n.locale.to_s]
    end

    { "default" => PUAVO_CONFIG['default_device_type'],
      "label" => I18n.t("host.types.register_label"),
      "title" => I18n.t("host.types.register_title"),
      "question" => I18n.t("host.types.register_question"),
      "list" => type_list }
  end
end
