class SambaGroup < LdapBase
  ldap_mapping( :dn_attribute => "cn",
                :prefix => "ou=Groups",
                :classes => ["top","posixGroup", "sambaGroupMapping"] )

  def self.add_uid_to_memberUid(cn, uid)
    object = self.find(cn)
    object.add_uid_to_memberUid(uid)
    object.save
  end

  def self.delete_uid_from_memberUid(cn, uid)
    object = self.find(cn)
    object.delete_uid_from_memberUid(uid)
    object.save
  end

  def add_uid_to_memberUid(uid)
    unless Array(self.memberUid).include?(uid)
      self.memberUid = Array(self.memberUid).push uid
    end
  end

  def delete_uid_from_memberUid(uid)
    self.memberUid = Array(self.memberUid) - Array(uid)
  end
end
