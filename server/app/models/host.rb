class Host < LdapBase
  ldap_mapping( :dn_attribute => "puavoId",
                :prefix => "ou=Hosts",
                :classes => ['top', 'device'] )

  @@objectClass_by_device_type = { "thinclient" => ["puavoNetbootDevice"],
    "fatclient" => ["puavoNetbootDevice"],
    "laptop" => ["puavoLocalbootDevice"],
    "workstation" => ["puavoLocalbootDevice"],
    "server" => ["puavoLocalbootDevice"],
    "netstand" => ["puavoLocalbootDevice"],
    "infotv" => ["puavoLocalbootDevice"] }

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
    { "default" => "laptop",
      "label" => "Device type",
      "title" => "Device type selection",
      "question" => "Select device type: ",
      "list" =>
      { "thinclient" =>
        { "label" => I18n.t("host.types.thinclient"),
          "classes" => ["puavoNetbootDevice"],
          "url" => "/devices/%s/devices/new.json?device_type=thinclient",
          "order" => "1" },
        "fatclient" =>
        { "label" => I18n.t("host.types.fatclient"),
          "classes" => ["puavoNetbootDevice"],
          "url" => "/devices/%s/devices/new.json?device_type=fatclient",
          "order" => "2" },
        "laptop" =>
        { "label" => I18n.t("host.types.laptop"),
          "classes" => ["puavoLocalbootDevice"],
          "url" => "/devices/%s/devices/new.json?device_type=laptop",
          "order" => "3" },
        "workstation" =>
        { "label" => I18n.t("host.types.workstation"),
          "classes" => ["puavoLocalbootDevice"],
          "url" => "/devices/%s/devices/new.json?device_type=workstation",
          "order" => "4" },
        "server" =>
        { "label" => I18n.t("host.types.server"),
          "classes" => ["puavoLocalbootDevice"],
          "url" => "/devices/servers/new.json?device_type=server",
          "order" => "5" },
        "netstand" =>
        { "label" => I18n.t("host.types.netstand"),
          "classes" => ["puavoLocalbootDevice"],
          "url" => "/devices/%s/devices/new.json?device_type=netstand",
          "order" => "6" },
        "infotv" =>
        { "label" => I18n.t("host.types.infotv"),
          "classes" => ["puavoLocalbootDevice"],
          "url" => "/devices/%s/devices/new.json?device_type=infotv" ,
          "order" => "7" } } }

  end
end
