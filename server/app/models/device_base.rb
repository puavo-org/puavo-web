class DeviceBase < LdapBase
  attr_accessor :host_certificate_request_send
  attr_accessor :host_certificate_request, :userCertificate, :rootca, :orgcabundle, :ldap_password

  before_validation :set_puavo_id, :set_password, :downcase_mac_addresses
  before_save :set_puppetclass, :set_parentNode

  validates_format_of :puavoHostname, :with => /^[0-9a-z-]+$/

  def host_certificate_request_send?
    host_certificate_request_send ? true : false
  end

  # Activeldap object's to_json method return Array by default.
  # E.g. @server.to_json -> [["puavoHostname", "puavoHostname 1"],["macAddress", "00-00-00-00-00-00-00-00"]]
  # When we use @server.attributes.to_json method we get Hash value. This is better and
  # following method make it automatically when we call to_json method.
  def to_json(options = {})
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
    # Create Hash by :methods name if :methods options is set.
    if options.has_key?(:methods)
      method_values = Array(options[:methods]).inject({ }) do |result, method|
        result.merge( { "#{method}" => self.send(method) } )
      end
      options.delete(:methods)
    end
    # Include method's values to the return value
    method_values.empty? ? self.attributes.to_json(options) :
      self.attributes.merge( method_values ).to_json(options)
  end

  def validate_on_create
    unless Host.validates_uniqueness_of_hostname(self.puavoHostname)
      # FIXME: localization
      errors.add "puavoHostname", "Hostname must be unique"
    end

    if host_certificate_request_send?
      if self.userCertificate.nil?
        # FIXME: Localization
        errors.add "userCertificate", "Unable to sign certificate"
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

  def puavoTag
    Array(super).join(" ")
  end

  def puavoTag=(tag_string)
    if tag_string.class == Array
      super(tag_string)
    elsif tag_string.class == String
      super( tag_string.split(" ") )
    end
  end

  private

  def http_puavo_ca
    http = Net::HTTP.new(PUAVO_CONFIG['puavo_ca']['host'], PUAVO_CONFIG['puavo_ca']['port'] || '80')
    http.use_ssl = true
    http.ca_file = PUAVO_CONFIG['puavo_ca']['ca_file']
    http.verify_mode = OpenSSL::SSL::VERIFY_PEER
    http.verify_depth = 5
    return http
  end

  def set_puppetclass
    self.puppetclass = PUAVO_CONFIG['device_types'][self.puavoDeviceType]['puppetclass']
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
    if PUAVO_CONFIG['device_types'][self.puavoDeviceType]['ldap_password']
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
    self.macAddress = self.macAddress.to_a.map{ |mac| mac.to_s.downcase }
  end
end
