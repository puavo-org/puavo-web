class ExternalApplication < LdapBase
  ldap_mapping(
    :dn_attribute => "puavoId",
    :prefix => "ou=Services"
  )

  before_validation :set_puavo_id
  validate :unique_domain

  def set_puavo_id
    self.puavoId = IdPool.next_puavo_id if self.puavoId.nil?
  end

  def unique_domain
    used_domains = self.class.all.map { |s| s.puavoServiceDomain }
    if used_domains.include?(self.puavoServiceDomain)
      errors.add(
        :puavoServiceDomain,
        "Domain #{ self.puavoServiceDomain } is not unique"
      )
    end
  end

end


