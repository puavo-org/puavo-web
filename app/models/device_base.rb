require 'date'
require 'net/http'
require_relative "./puavo_conf_mixin"
require_relative "./puavo_tag_mixin"

class DeviceBase < LdapBase
  include BooleanAttributes
  include PuavoConfMixin
  include PuavoTagMixin
  include Mountpoint

  attr_accessor :host_certificate_request_send, :image
  attr_accessor :host_certificate_request, :hostCertificates, :hostCertificates, :rootca, :orgcabundle, :ldap_password
  attr_reader :userCertificate  # for old puavo-register code

  before_validation( :set_puavo_id,
                     :set_password,
                     :downcase_mac_addresses )
  before_save :set_puppetclass, :set_parentNode, :set_puavo_mountpoint

  IA5STRING_CHARACTERS = "A-Za-z0-9" + Regexp.escape('@[\]^_\'{|}!"#%&()*+,-./:;<=>\?')
  PRINTABLE_STRING_CHARACTERS = "A-Za-z0-9" + Regexp.escape('()+,-./:\? ')

  validate :validate, :validate_puavoconf

  def self.image_size
    { width: 220, height: 220 }
  end


  def host_certificate_request_send?
    host_certificate_request_send ? true : false
  end

  def self.find_by_hostname(hostname)
    Device.find(:first, :attribute => "puavoHostname", :value => hostname)
  end

  def userCertificate
    Array(self.hostCertificates).first
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
                            :hostCertificates,
                            :rootca,
                            :orgcabundle,
                            :ldap_password,
                            :userCertificate,
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
    if host_certificate_request_send? then
      if self.hostCertificates.nil? || self.hostCertificates.empty? then
        # FIXME: Localization
        errors.add 'hostCertificates', 'Unable to sign certificates'
      end
    end
  end

  def validate
    # Validate format of puavoHostname
    unless self.puavoHostname.to_s =~ /^[0-9a-z-]+$/
      errors.add( :puavoHostname,
                  I18n.t("activeldap.errors.messages.device.puavoHostname.invalid_characters" ) )
    end

    unless !puavoHostname.empty? && Host.validates_uniqueness_of_hostname(self)
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

    # Validate the image, if set. Must be done here, because if the file is not a valid image file,
    # it will cause an exception in ImageMagick.
    if self.image && !self.image.path.to_s.empty?
      begin
        resize_image
      rescue
        errors.add(:image, I18n.t('activeldap.errors.messages.image_failed'))
      end
    end
  end

  def sign_certificate(organisation_key, dn, password)
    begin
      self.host_certificate_request_send = true
      http = http_puavo_ca
      request = Net::HTTP::Post.new('/certificates.json',
                                    { 'Content-Type' => 'application/json' })
      request.basic_auth(dn, password)
      response = http.request(request,
                              {
                                'certificate' => {
                                  'fqdn'                     => self.puavoHostname + "." + LdapOrganisation.current.puavoDomain,
                                  'host_certificate_request' => self.host_certificate_request,
                                  'organisation'             => organisation_key,
                                }
                              }.to_json)

      case response.code
      when /^2/
        # successful request
        self.hostCertificates \
          = [ JSON.parse(response.body)['certificate'] ]
        logger.debug "Certificates: #{ self.hostCertificates.inspect }\n"
      else
        raise "response code: #{response.code}, puavoHostname: #{self.puavoHostname}"
      end
    rescue StandardError => e
      logger.info "ERROR: Unable to sign certificate"
      logger.info "Exception: #{ e.message }"
    end
  end

  def has_pending_reset
    self.puavoDeviceReset \
      && (reset_state = JSON.parse(self.puavoDeviceReset) rescue nil) \
      && reset_state.kind_of?(Hash) \
      && reset_state['request-time'] \
      && !reset_state['request-fulfilled']
  end

  def set_reset_mode(current_user)
    reset_pin = DateTime.now.strftime('%y%V')   # this is not an actual secret

    user_uid        = current_user.uid        || 'NO_UID'
    user_given_name = current_user.given_name || 'NO_GIVEN_NAME'
    user_surname    = current_user.surname    || 'NO_SURNAME'
    user_string     = "#{ user_given_name } #{ user_surname } (#{ user_uid })"

    self.puavoDeviceReset = {
      'from'              => user_string,
      'mode'              => 'ask_pin',
      'operation'         => 'reset',
      'pin'               => reset_pin,
      'request-fulfilled' => nil,
      'request-time'      => DateTime.now.to_s,
      'run-immediately'   => 'false',
    }.to_json
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
    rescue StandardError => e
      logger.info "Unable to revoke certificate"
      logger.info "Exception: #{ e.message }"
    end
  end

  def get_certificate(organisation_key, dn, password)
    begin
      http = http_puavo_ca
      fqdn = "#{ self.puavoHostname }.#{ LdapOrganisation.current.puavoDomain }"
      uri_path = "/certificates/show_by_fqdn.json?fqdn=#{ fqdn }"
      request = Net::HTTP::Get.new(uri_path)
      request.basic_auth(dn, password)
      response = http.request(request)
      case response.code
      when /^2/
        # successful request
        self.hostCertificates = JSON.parse(response.body)['certificates']
      else
        raise "response code: #{response.code}, puavoHostname: #{self.puavoHostname}"
      end
    rescue StandardError => e
      logger.info "Unable to get certificate"
      logger.info "Exception: #{ e.message }"
    end
  end

  def get_ca_certificate(organisation_key)
    begin
      http = http_puavo_ca

      request = Net::HTTP::Get.new('/certificates/rootca.text')
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
    rescue StandardError => e
      logger.info "Unable to get CA certificate"
      logger.info "Exception: #{ e.message }"
    end
  end


  def parent
    if self.attributes.include?("puavoSchool") && !self.puavoSchool.nil?
      begin
        return School.find(self.puavoSchool)
      rescue ActiveLdap::EntryNotFound => e
        return nil
      end
    end
  end

  def self.uid_to_dn(uid)
    return nil if uid.nil? || uid.empty?

    uid = Net::LDAP::Filter.escape( uid )
    filter = "(uid=#{ uid })"

    user_dn = nil
    users = User.search_as_utf8( :filter => filter,
                                 :scope => :one,
                                 :attributes => [] ).each do |dn, attributes|
      user_dn = dn
    end

    return user_dn
  end

  private

  def http_puavo_ca
    http = Net::HTTP.new(Puavo::CONFIG['puavo_ca']['host'], Puavo::CONFIG['puavo_ca']['port'] || '80')
    if Puavo::CONFIG['puavo_ca']['use_ssl']
      http.use_ssl = true
      http.ca_file = Puavo::CONFIG['puavo_ca']['ca_file']
      http.verify_mode = OpenSSL::SSL::VERIFY_PEER
    end
    return http
  end

  def set_puppetclass
    self.puppetclass = Puavo::CONFIG['device_types'][self.puavoDeviceType]['puppetclass']
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
    if Puavo::CONFIG['device_types'][self.puavoDeviceType]['ldap_password']
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
    self.macAddress = Array(self.macAddress).map do |mac|
      mac.to_s.gsub('-', ':').downcase
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
     { :original_attribute_name => "puavoConf",
       :new_attribute_name => "puavoconf",
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
     { :original_attribute_name => "puavoDeviceType",
       :new_attribute_name => "device_type",
       :value_block => lambda{ |value| Array(value).first } },
     { :original_attribute_name => "puavoDeviceImage",
       :new_attribute_name => "device_image",
       :value_block => lambda{ |value| Array(value).first } },
     { :original_attribute_name => "puavoDeviceMonitorsXML",
       :new_attribute_name => "monitors_xml",
       :value_block => lambda{ |value| Array(value).first } },
     { :original_attribute_name => "puavoDeviceReset",
       :new_attribute_name => "reset",
       :value_block => lambda{ |value| Array(value).first } } ]
  end
end
