# Base class for the School and Group classes.
# Also School is group on the LDAP and operating systems.
class BaseGroup < LdapBase
  before_validation :set_special_ldap_value
  validate :validate_unique_cn

  def id
    self.puavoId.to_s unless self.puavoId.nil?
  end

  private

  def set_special_ldap_value
    set_gid_number if self.gidNumber.nil?
    self.puavoId = IdPool.next_puavo_id if self.puavoId.nil?
    set_samba_settings if self.sambaSID.nil?
  end

  def set_gid_number
    self.gidNumber = IdPool.next_gid_number
  end

  def set_samba_settings
    self.sambaGroupType = 2
    self.sambaSID = SambaDomain.next_samba_sid
  end

  def validate_unique_cn
    # cn attribute must be unique on the group and school model.
    # cn == group name (operating system)

    cn_escape = Net::LDAP::Filter.escape( self.cn )

    filter = "(&" +
      "(|(objectClass=puavoSchool)(objectClass=puavoEduGroup))" +
      "(cn=#{ cn_escape })" +
      ")"
    group_ids = BaseGroup.search( :filter => filter,
                                  :scope => :sub ).map{ |u| u.last["puavoId"].first }

    if self.puavoId
      group_ids.delete_if{ |id| self.puavoId.to_i == id.to_i }
    end

    if self.cn.empty? || ! group_ids.empty?
      errors.add :cn, I18n.t("activeldap.errors.messages.taken",
                             :attribute => I18n.t("activeldap.attributes.#{self.class.to_s.downcase}.cn") )
    end
  end
end
