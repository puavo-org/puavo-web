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
      self.ldap_modify_operation( :add, [{"memberUid" => [uid]}] )
    end
  end

  def delete_uid_from_memberUid(uid)
    begin
      self.ldap_modify_operation( :delete, [{"memberUid" => [uid]}] )
    rescue ActiveLdap::LdapError::NoSuchAttribute
      logger.warn "Cannot remove nonexistent memberUid=#{ uid } from SambaGroup #{ dn }"
    end
  end
end
