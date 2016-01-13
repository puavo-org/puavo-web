require_relative "../lib/samba_attrs"

module PuavoRest

class Group < LdapModel
  include SambaAttrs

  ldap_map :dn, :dn
  ldap_map :puavoEduGroupType, :type, LdapConverters::SingleValue
  ldap_map :puavoId, :id, LdapConverters::SingleValue
  ldap_map :puavoExternalId, :external_id, LdapConverters::SingleValue
  ldap_map :objectClass, :object_classes, LdapConverters::ArrayValue
  ldap_map :cn, :abbreviation
  ldap_map :displayName, :name
  ldap_map :puavoSchool, :school_dn
  ldap_map :gidNumber, :gid_number, LdapConverters::Number
  ldap_map(:puavoPrinterQueue, :printer_queue_dns){ |v| Array(v) }
  ldap_map :memberUid, :member_usernames, LdapConverters::ArrayValue
  ldap_map :member, :member_dns, LdapConverters::ArrayValue
  ldap_map :puavoEduGroupType, :type, LdapConverters::SingleValue

  before :create do
    if Array(object_classes).empty?
      self.object_classes = ['top', 'posixGroup', 'puavoEduGroup','sambaGroupMapping']
    end

    if id.nil?
      self.id = IdPool.next_id("puavoNextId").to_s
    end

    if gid_number.nil?
      self.gid_number = IdPool.next_id("puavoNextGidNumber")
    end

    if dn.nil?
      self.dn = "puavoId=#{ id },#{ self.class.ldap_base }"
    end

    write_samba_attrs
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
    by_ldap_attr(:member, dn, :multiple => true)
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
    set_samba_sid

    write_raw(:sambaGroupType, ["2"])
  end

  # Cached organisation query
  def organisation
    @organisation ||= Organisation.by_dn(self.class.organisation["base"])
  end


end
end
