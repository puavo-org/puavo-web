# frozen_string_literal: true

class SambaGroup < LdapBase
  ldap_mapping dn_attribute: 'cn',
               prefix: 'ou=Groups',
               classes: %w[top posixGroup sambaGroupMapping]

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
      self.ldap_modify_operation(:add, [{ 'memberUid' => [uid] }])
    end
  rescue ActiveLdap::LdapError::TypeOrValueExists
    # Just move on; LDAP isn't a relational DB, this can happen and it'll get fixed soon
  end

  def delete_uid_from_memberUid(uid)
    self.ldap_modify_operation(:delete, [{ 'memberUid' => [uid] }])
  rescue ActiveLdap::LdapError::NoSuchAttribute
    logger.warn "Cannot remove nonexistent memberUid=#{uid} from SambaGroup #{dn}"
  end
end
