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

  # Find all external files configured in config/puavo_external_files.yml
  def self.find_configured(config=Puavo::EXTERNAL_FILES)

    # Create or ldap filter
    filter = "(|" 
    filter += config.map do |o|
      "(cn=#{ o["name"] })"
    end.join("")
    filter += ")"

    return ExternalFile.find(:all, :filter => filter)
  end

  def self.find_or_create_by_cn(cn)
    if f = ExternalFile.find(:first, :attribute => "cn", :value => cn)
      return f
    end

    f = ExternalFile.new
    f.cn = cn
    return f
  end

  def as_json(*args)
    return {
      "id" => puavoId,
      "name" => cn,
      "hash" => puavoDataHash
    }
  end

end
