class ExternalApplication < LdapBase
  ldap_mapping(
    :dn_attribute => "puavoId",
    :prefix => "ou=Services"
  )

  before_validation :set_puavo_id

  def set_puavo_id
    self.puavoId = IdPool.next_puavo_id if self.puavoId.nil?
  end


end


