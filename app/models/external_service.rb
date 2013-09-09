class ExternalService < ActiveLdap::Base
  include Puavo::Connection

  ldap_mapping(
    :dn_attribute => "puavoId",
    :prefix => "ou=Services"
  )

  before_validation :set_puavo_id, :ensure_slash_in_prefix
  validate :unique_domain_and_prefix

  def set_puavo_id
    self.puavoId = IdPool.next_puavo_id if self.puavoId.nil?
  end

  def ensure_slash_in_prefix
    if self.puavoServicePathPrefix && self.puavoServicePathPrefix[0] != "/"
      self.puavoServicePathPrefix = "/#{ self.puavoServicePathPrefix }"
    end
  end

  def domain_with_prefix
    "#{ self.puavoServiceDomain }#{ self.puavoServicePathPrefix }"
  end

  def unique_domain_and_prefix

    used = self.class.all.select do |s|
      self.new_entry? || s.dn != self.dn
    end.map do |s|
      s.domain_with_prefix
    end

    if used.include?(self.domain_with_prefix)
      errors.add(
        :puavoServiceDomain,
        "Domain #{ self.domain_with_prefix } is not unique"
      )
    end
  end

end


