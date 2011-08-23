class LdapBase < ActiveLdap::Base
  include Puavo::Connection

  def ldap_modify_operation(type, attributes)
    self.class.ldap_modify_operation(self.dn, type, attributes)
  end

  def self.ldap_modify_operation(dn, type, attributes)
    ldif = ActiveLdap::LDIF.new
    record = ActiveLdap::LDIF::ModifyRecord.new(dn)
    ldif << record
    attributes.each do |attribute|
      record.add_operation(type, attribute.keys.first, [], attribute)
    end
    LdapBase.load(ldif.to_s)
  end

  def <=>(other_object)
    self.displayName.to_s <=> other_object.displayName.to_s
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

    method_values = { }
    # Create Hash by :methods name if :methods options is set.
    if options.has_key?(:methods)
      method_values = Array(options[:methods]).inject({ }) do |result, method|
        result.merge( { "#{method}" => self.send(method) } )
      end
      options.delete(:methods)
    end
    # Include method's values to the return value'
    method_values.empty? ? allowed_attributes.to_json(options) :
      allowed_attributes.merge( method_values ).to_json(options)
  end
end
