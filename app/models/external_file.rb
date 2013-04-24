class ExternalFile < LdapBase

  before_validation :set_dn, :set_hash

  ldap_mapping(
    :dn_attribute => "puavoId",
    :prefix => "ou=Files,ou=Desktops",
    :classes => ["top", "puavoFile"]
  )

  def set_dn
    self.puavoId = IdPool.next_puavo_id if self.puavoId.nil?
  end

  def set_hash
    sha1 = Digest::SHA1.new
    sha1.update(puavoData)
    self.puavoDataHash = sha1.to_s
  end

end
