module PuavoRest

class Group < LdapModel
  ldap_map :dn, :dn
  ldap_map :puavoId, :id, LdapConverters::Number
  ldap_map :objectClass, :object_classes, LdapConverters::ArrayValue
  ldap_map :cn, :abbreviation
  ldap_map :displayName, :name
  ldap_map :puavoSchool, :school_dn
  #ldap_map(:gidNumber, :gid_number){ |v| Array(v).first.to_i }
  ldap_map :gidNumber, :gid_number, LdapConverters::Number
  ldap_map(:puavoPrinterQueue, :printer_queue_dns){ |v| Array(v) }
  ldap_map :memberUid, :member_usernames, LdapConverters::ArrayValue
  ldap_map :member, :member_dns, LdapConverters::ArrayValue

  before :create do
    if Array(object_classes).empty?
      self.object_classes = ['top', 'posixGroup', 'puavoEduGroup','sambaGroupMapping']
    end

    if id.nil?
      self.id = IdPool.next_id("puavoNextId")
    end

    if gid_number.nil?
      self.gid_number = IdPool.next_id("puavoNextGidNumber")
    end

    if dn.nil?
      self.dn = "puavoId=#{ id },#{ self.class.ldap_base }"
    end

    write_samba_attrs

    # FIXME set sambaSID and sambaGroupType
  end

  computed_attr :school_id
  def school_id
    school_dn.to_s.match(/puavoid=([0-9]+)/i)[1]
  end

  def self.base_filter
    "(objectClass=puavoEduGroup)"
  end

  def self.ldap_base
    "ou=Groups,#{ organisation["base"] }"
  end

  def self.by_user_dn(dn)
    by_ldap_attr(:member, dn, :multi)
  end

  def printer_queues
    PrinterQueue.by_dn_array(printer_queue_dns)
  end

  # Add member to group. Append username to `memberUid` and dn to `member` ldap
  # attributes
  #
  # @param user [User] user to add as member
  def add_member(user)
    add(:member_usernames, user.username)
    add(:member_dns, user.dn)
  end

  # Remove member for the group
  #
  # @param user [User] user to add as member
  def remove_member(user)
    remove(:member_usernames, user.username)
    remove(:member_dns, user.dn)
  end

  # Does user belong to this group
  #
  # @param user [User] user to add as member
  # @return [Boolean]
  def has?(user)
    return member_usernames.include?(user.username)
  end

  # Write internal samba attributes. Implementation is based on the puavo-web
  # code is not actually tested on production systems
  def write_samba_attrs
    all_samba_domains = SambaDomain.all

    if all_samba_domains.empty?
      raise InternalError, :user => "Cannot find samba domain"
    end

   # Each organisation should have only one
    if all_samba_domains.size > 1
      raise InternalError, :user => "Too many Samba domains"
    end

    samba_domain = all_samba_domains.first

    pool_key = "puavoNextSambaSID:#{ samba_domain.domain }"

    if IdPool.last_id(pool_key).nil?
      IdPool.set_id!(pool_key, samba_domain.legacy_rid)
    end

    rid = IdPool.next_id(pool_key)

    write_raw(:sambaGroupType, ["2"])
    write_raw(:sambaSID, ["#{ samba_domain.sid }-#{ rid - 1}"])

#    samba_sid = Array(get_raw(:sambaSID)).first
#    if samba_sid && new?
#      res = LdapModel.raw_filter(organisation["base"], "(sambaSID=#{ escape samba_sid })")
#      if res && !res.empty?
#        other_dn = res.first["dn"].first
#        # Internal attribute, use underscore prefix to indicate that
#        add_validation_error(:__sambaSID, :sambaSID_not_unique, "#{ samba_sid } is already used by #{ other_dn }")
#      end
#    end
    # Redo validation for samba attrs
    #assert_validation
  end

end
end
