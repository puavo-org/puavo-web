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
end
