# Base class for the School and Group classes.
# Also School is group on the LDAP and operating systems.
class BaseGroup < LdapBase
  before_validation :set_special_ldap_value

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

  def validate_on_create
    # cn attribute must be unique on the group and school model.
    # cn == group name (operating system)
    if self.cn.empty? || Group.find(:first, :attribute => "cn", :value => self.cn) ||
        School.find(:first, :attribute => "cn", :value => self.cn)
      errors.add :cn, I18n.t("activeldap.errors.messages.taken",
                             :attribute => I18n.t("activeldap.attributes.#{self.class.to_s.downcase}.cn") )
    end
  end
end
