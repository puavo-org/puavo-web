class LdapBase < ActiveLdap::Base
  include Puavo::Connection if defined?(Puavo::Connection)

  attr_accessor :host_certificate_request_send
  attr_accessor :host_certificate_request, :userCertificate, :cacerts, :new_password

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
      options[:methods] = [:host_certificate_request, :userCertificate, :cacerts, :new_password]
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
                                  'fqdn'                     => self.puavoHostname + "." + LdapOrganisation.first.organizationName,
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
      request = Net::HTTP::Delete.new("/certificates/revoke.json?fqdn=#{self.puavoHostname + "." + LdapOrganisation.first.organizationName}")
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
      request = Net::HTTP::Get.new("/certificates/show_by_fqdn.json?fqdn=#{self.puavoHostname + "." + LdapOrganisation.first.organizationName}")
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
      request = Net::HTTP::Get.new("/certificates/ca.text?org=#{organisation_key}")
      response = http.request(request)
      case response.code
      when /^2/
        # successful request
        self.cacerts = response.body
      else
        raise "response code: #{response.code}, puavoHostname: #{self.puavoHostname}"
      end
    rescue Exception => e
      logger.info "Unable to get CA certificate"
      logger.info "Exception: #{e}"
    end
  end

  private

  def http_puavo_ca
    Net::HTTP.new(PUAVO_CONFIG['puavo_ca']['host'], PUAVO_CONFIG['puavo_ca']['port'] || '80')
  end
end
