class DeviceBase < LdapBase
  attr_accessor :host_certificate_request_send, :image
  attr_accessor :host_certificate_request, :userCertificate, :rootca, :orgcabundle, :ldap_password

  before_validation :set_puavo_id, :set_password, :downcase_mac_addresses, :resize_image
  before_save :set_puppetclass, :set_parentNode

  IA5STRING_CHARACTERS = "A-Za-z0-9" + Regexp.escape('@[\]^_\'{|}!"#%&()*+,-./:;<=>\?')
  PRINTABLE_STRING_CHARACTERS = "A-Za-z0-9" + Regexp.escape('()+,-./:\? ')

  def host_certificate_request_send?
    host_certificate_request_send ? true : false
  end

  # Activeldap object's to_json method return Array by default.
  # E.g. @server.to_json -> [["puavoHostname", "puavoHostname 1"],["macAddress", "00-00-00-00-00-00-00-00"]]
  # When we use @server.attributes.to_json method we get Hash value. This is better and
  # following method make it automatically when we call to_json method.
  def to_json(options = {})
    allowed_attributes = self.attributes
    allowed_attributes.delete_if do |attribute, value|
      !self.schema.attribute(attribute).syntax.human_readable?
    end

    unless options.has_key?(:methods)
      # Set default methods list
      options[:methods] = [ :host_certificate_request,
                            :userCertificate,
                            :rootca,
                            :orgcabundle,
                            :ldap_password,
                            :host_configuration ]
    end
    method_values = { }

    allowed_attributes["dn"] = dn.to_s

    # Create Hash by :methods name if :methods options is set.
    if options.has_key?(:methods)
      method_values = Array(options[:methods]).inject({ }) do |result, method|
        result.merge( { "#{method}" => self.send(method) } )
      end
      options.delete(:methods)
    end
    # Include method's values to the return value
    method_values.empty? ? allowed_attributes.to_json(options) :
      allowed_attributes.merge( method_values ).to_json(options)
  end

  def validate_on_create
    if host_certificate_request_send?
      if self.userCertificate.nil?
        # FIXME: Localization
        errors.add "userCertificate", "Unable to sign certificate"
      end
    end
  end

  def validate
    # Validate format of puavoHostname
    unless self.puavoHostname.to_s =~ /^[0-9a-z-]+$/
      errors.add( :puavoHostname,
                  I18n.t("activeldap.errors.messages.device.puavoHostname.invalid_characters" ) )
    end

    unless Host.validates_uniqueness_of_hostname(self)
      errors.add :puavoHostname, I18n.t('activeldap.errors.messages.taken',
                                        :attribute => I18n.t('activeldap.attributes.device.puavoHostname'))
    end

    unless self.puavoPurchaseURL.to_s.empty?
       unless self.puavoPurchaseURL.to_s =~ URI::regexp(%w(http https))
         self.puavoPurchaseURL = 'http://' + self.puavoPurchaseURL.to_s
       end
    end

    # macAddress is required attribute if device is bootable device (server, fatclient, thinclient, laptop etc.)
    if self.classes.include?('puavoNetbootDevice') ||
        self.classes.include?('puavoLocalbootDevice') ||
        self.classes.include?('puavoServer')
      if self.macAddress.to_s.empty?
        errors.add :macAddress, I18n.t('activeldap.errors.messages.taken',
                                       :attribute => I18n.t('activeldap.attributes.device.macAddress'))
      end
    end

    # Validate format of macAddress
    Array(self.macAddress).each do |mac|
      unless mac.to_s.empty?
        unless mac =~ /^([0-9a-f]{2}[:]){5}[0-9a-f]{2}$/
          errors.add( :macAddress,
                      I18n.t("activeldap.errors.messages.device.macAddress.invalid_characters" ) )
          break
        end
      end
    end

    # Validate format of serialNumber
    #
    # Remove spaces from the end of the string
    self.serialNumber = self.serialNumber.to_s.rstrip
    if !self.serialNumber.to_s.empty? && (self.serialNumber.to_s =~ /^[#{PRINTABLE_STRING_CHARACTERS}]+$/).nil?
      unless errors[:serialNumber].nil?
        errors.delete(:serialNumber)
      end
      errors.add( :serialNumber,
                  I18n.t("activeldap.errors.messages.invalid_characters",
                         :attribute => I18n.t('activeldap.attributes.device.serialNumber') ) )
    end

    # Validate format of puavoLongitude and puavoLatitude
    if !self.puavoLongitude.to_s.empty? && (self.puavoLongitude =~ /^[#{IA5STRING_CHARACTERS}]+$/).nil?
      errors.add( :puavoLongitude,
                  I18n.t("activeldap.errors.messages.invalid_characters",
                         :attribute => I18n.t('activeldap.attributes.device.puavoLongitude') ) )
    end
    if !self.puavoLatitude.to_s.empty? && (self.puavoLatitude.to_s =~ /^[#{IA5STRING_CHARACTERS}]+$/).nil?
      errors.add( :puavoLatitude,
                  I18n.t("activeldap.errors.messages.invalid_characters",
                         :attribute => I18n.t('activeldap.attributes.device.puavoLatitude') ) )
    end

    # Valdiate format of ipHostNumber
    if self.classes.include?('puavoOtherDevice') || self.classes.include?('puavoPrinter')
      if !self.ipHostNumber.to_s.empty? && (self.ipHostNumber =~ /^([0-9]{1,3}[.]){3}[0-9]{1,3}$/).nil?
        errors.add( :ipHostNumber,
                    I18n.t("activeldap.errors.messages.invalid",
                           :attribute => I18n.t('activeldap.attributes.device.ipHostNumber') ) )
      end
    end
  end

  def sign_certificate(organisation_key, dn, password)
    begin
      self.host_certificate_request_send = true
      http = http_puavo_ca
      request = Net::HTTP::Post.new("/certificates.json?org=#{organisation_key}",
                                    { 'Content-Type' => 'application/json' })
      request.basic_auth(dn, password)
      response = http.request(request,
                              {
                                'certificate' => {
                                  'fqdn'                     => self.puavoHostname + "." + LdapOrganisation.current.puavoDomain,
                                  'host_certificate_request' => self.host_certificate_request,
                                }
                              }.to_json)

      case response.code
      when /^2/
        # successful request
        self.userCertificate = JSON.parse(response.body)["certificate"]["certificate"]
        logger.debug "Certificate:\n" + self.userCertificate.inspect
      else
        raise "response code: #{response.code}, puavoHostname: #{self.puavoHostname}"
      end
    rescue Exception => e
      logger.info "ERROR: Unable to sign certificate"
      logger.info "Exception: #{e}"
    end
  end

  def revoke_certificate(organisation_key, dn, password)
    begin
      http = http_puavo_ca
      request = Net::HTTP::Delete.new("/certificates/revoke.json?fqdn=#{self.puavoHostname + "." + LdapOrganisation.current.puavoDomain}")
      request.basic_auth(dn, password)
      response = http.request(request)
      case response.code
      when /^2/
        # successful request
      else
        raise "response code: #{response.code}, puavoHostname: #{self.puavoHostname}"
      end
    rescue Exception => e
      logger.info "Unable to revoke certificate"
      logger.info "Exception: #{e}"
    end
  end

  def get_certificate(organisation_key, dn, password)
    begin
      http = http_puavo_ca
      request = Net::HTTP::Get.new("/certificates/show_by_fqdn.json?fqdn=#{self.puavoHostname + "." + LdapOrganisation.current.puavoDomain}")
      request.basic_auth(dn, password)
      response = http.request(request)
      case response.code
      when /^2/
        # successful request
        self.userCertificate = JSON.parse(response.body)["certificate"]["certificate"]
      else
        raise "response code: #{response.code}, puavoHostname: #{self.puavoHostname}"
      end
    rescue Exception => e
      logger.info "Unable to get certificate"
      logger.info "Exception: #{e}"
    end
  end

  def get_ca_certificate(organisation_key)
    begin
      http = http_puavo_ca

      request = Net::HTTP::Get.new("/certificates/rootca.text?org=#{organisation_key}")
      response = http.request(request)
      case response.code
      when /^2/
        # successful request
        self.rootca = response.body
      else
        raise "response code: #{response.code}, puavoHostname: #{self.puavoHostname}"
      end

      request = Net::HTTP::Get.new("/certificates/orgcabundle.text?org=#{organisation_key}")
      response = http.request(request)
      case response.code
      when /^2/
        # successful request
        self.orgcabundle = response.body
      else
        raise "response code: #{response.code}, puavoHostname: #{self.puavoHostname}"
      end
    rescue Exception => e
      logger.info "Unable to get CA certificate"
      logger.info "Exception: #{e}"
    end
  end

# FIXME
#  def puavoTag
#    Array(super).join(" ")
#  end
#
#  def puavoTag=(tag_string)
#    if tag_string.class == Array
#      super(tag_string)
#    elsif tag_string.class == String
#      super( tag_string.split(" ") )
#    end
#  end

  private

  def http_puavo_ca
    http = Net::HTTP.new(Puavo::DEVICE_CONFIG['puavo_ca']['host'], Puavo::DEVICE_CONFIG['puavo_ca']['port'] || '80')
    http.use_ssl = true
    http.ca_file = Puavo::DEVICE_CONFIG['puavo_ca']['ca_file']
    http.verify_mode = OpenSSL::SSL::VERIFY_PEER
    http.verify_depth = 5
    return http
  end

  def set_puppetclass
    self.puppetclass = Puavo::DEVICE_CONFIG['device_types'][self.puavoDeviceType]['puppetclass']
  end

  def host_configuration
    hostname, *domain_a = LdapOrganisation.current.puavoDomain.split('.')
    domain = domain_a.join('.')
    if self.class == Device || self.class == Server
      return {
        'devicetype' => self.puavoDeviceType,
        'kerberos_realm' => LdapOrganisation.current.puavoKerberosRealm,
        'puppet_server' => "#{hostname}.puppet.#{domain}" }
    end
  end

  def set_password
    if Puavo::DEVICE_CONFIG['device_types'][self.puavoDeviceType]['ldap_password']
      unless self.classes.include?('simpleSecurityObject')
        self.add_class('simpleSecurityObject')
      end
      if self.userPassword.nil? || self.userPassword.empty?
        characters = ("a".."z").to_a + ("0".."9").to_a
        self.ldap_password = Array.new(40) { characters[rand(characters.size)] }.join
        self.userPassword = Server.ssha_hash(self.ldap_password)
      end
    end
  end

  def set_puavo_id
    self.puavoId = IdPool.next_puavo_id if attribute_names.include?("puavoId") && self.puavoId.nil?
    self.cn = self.puavoHostname
  end

  def set_parentNode
    self.parentNode = LdapOrganisation.current.puavoDomain
  end

  def downcase_mac_addresses
    self.macAddress = self.macAddress.to_a.map do |mac|
      mac.to_s.gsub('-', ':').downcase
    end
  end

  def resize_image
    if self.image.class == Tempfile
      image_orig = Magick::Image.read(self.image.path).first
      self.jpegPhoto = image_orig.resize_to_fit(220,220).to_blob
    end
  end

  # Building hash for to_json method with better name of attributes
  #  * data argument may be Device or Hash
  def self.build_hash_for_to_json(data)
    new_device_hash = {}

    device_attributes = self.json_attributes

    device_attributes.each do |attr|
      attribute_value = data.class == Hash ? data[attr[:original_attribute_name]] : data.send(attr[:original_attribute_name])
      new_device_hash[attr[:new_attribute_name]] = attr[:value_block].call(attribute_value)
    end
    return new_device_hash
  end

  def self.json_attributes
    # Note: value of attribute may be raw ldap value eg. { puavoHostname => ["thinclient-01"] }
    [
     { :original_attribute_name => "description",
       :new_attribute_name => "description",
       :value_block => lambda{ |value| Array(value).first } },
     { :original_attribute_name => "ipHostNumber",
       :new_attribute_name => "ip_address",
       :value_block => lambda{ |value| Array(value).first } },
     { :original_attribute_name => "jpegPhoto",
       :new_attribute_name => "image",
       :value_block => lambda{ |value| Array(value).first } },
     { :original_attribute_name => "macAddress",
       :new_attribute_name => "mac_address",
       :value_block => lambda{ |value| Array(value).first } },
     { :original_attribute_name => "puavoDefaultPrinter",
       :new_attribute_name => "default_printer",
       :value_block => lambda{ |value| Array(value).first } },
     { :original_attribute_name => "puavoDeviceAutoPowerOffMode",
       :new_attribute_name => "auto_power_mode",
       :value_block => lambda{ |value| Array(value).first } },
     { :original_attribute_name => "puavoDeviceBootMode",
       :new_attribute_name => "boot_mode",
       :value_block => lambda{ |value| Array(value).first } },
     { :original_attribute_name => "puavoDeviceManufacturer",
       :new_attribute_name => "manufacturer",
       :value_block => lambda{ |value| Array(value).first } },
     { :original_attribute_name => "puavoDeviceModel",
       :new_attribute_name => "model",
       :value_block => lambda{ |value| Array(value).first } },
     { :original_attribute_name => "puavoLatitude",
       :new_attribute_name => "latitude",
       :value_block => lambda{ |value| Array(value).first } },
     { :original_attribute_name => "puavoLocationName",
       :new_attribute_name => "location_name",
       :value_block => lambda{ |value| Array(value).first } },
     { :original_attribute_name => "puavoLongitude",
       :new_attribute_name => "longitude",
       :value_block => lambda{ |value| Array(value).first } },
     { :original_attribute_name => "puavoPurchaseDate",
       :new_attribute_name => "purchase_date",
       :value_block => lambda{ |value| Array(value).first } },
     { :original_attribute_name => "puavoPurchaseLocation",
       :new_attribute_name => "purchase_location",
       :value_block => lambda{ |value| Array(value).first } },
     { :original_attribute_name => "puavoPurchaseURL",
       :new_attribute_name => "purchase_url",
       :value_block => lambda{ |value| Array(value).first } },
     { :original_attribute_name => "puavoSupportContract",
       :new_attribute_name => "support_contract",
       :value_block => lambda{ |value| Array(value).first } },
     { :original_attribute_name => "puavoTag",
       :new_attribute_name => "tags",
       :value_block => lambda{ |value| Array(value).first } },
     { :original_attribute_name => "puavoWarrantyEndDate",
       :new_attribute_name => "warranty_end_date",
       :value_block => lambda{ |value| Array(value).first } },
     { :original_attribute_name => "serialNumber",
       :new_attribute_name => "serialnumber",
       :value_block => lambda{ |value| Array(value).first } },
     { :original_attribute_name => "puavoHostname",
       :new_attribute_name => "hostname",
       :value_block => lambda{ |value| Array(value).first } },
     { :original_attribute_name => "puavoId",
       :new_attribute_name => "puavo_id",
       :value_block => lambda{ |value| Array(value).first } },
     { :original_attribute_name => "puavoDeviceKernelVersion",
       :new_attribute_name => "kernel_version",
       :value_block => lambda{ |value| Array(value).first } },
     { :original_attribute_name => "puavoDeviceKernelArguments",
       :new_attribute_name => "kernel_arguments",
       :value_block => lambda{ |value| Array(value).first } },
     { :original_attribute_name => "puavoDeviceXrandr",
       :new_attribute_name => "xrandr",
       :value_block => lambda{ |value| Array(value).first } },
     { :original_attribute_name => "puavoDeviceXrandrDisable",
       :new_attribute_name => "xrandr_disable",
       :value_block => lambda{ |value| Array(value).first } },
     { :original_attribute_name => "puavoDeviceType",
       :new_attribute_name => "device_type",
       :value_block => lambda{ |value| Array(value).first } },
     { :original_attribute_name => "puavoDeviceImage",
       :new_attribute_name => "device_image",
       :value_block => lambda{ |value| Array(value).first } } ]
  end
end
