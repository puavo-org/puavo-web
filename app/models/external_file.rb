class ExternalFile < LdapBase

  before_validation :set_dn

  def set_dn
    self.puavoId = IdPool.next_puavo_id if self.puavoId.nil?
  end

  ldap_mapping(
    :dn_attribute => "puavoId",
    :prefix => "ou=Files,ou=Desktops",
    :classes => ["top", "puavoFile"]
  )
end
