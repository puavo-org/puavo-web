# frozen_string_literal: true

# Base class for the School and Group classes.
# Also School is group on the LDAP and operating systems.
class BaseGroup < LdapBase
  before_validation :set_special_ldap_value
  validate :validate_unique_cn

  def id
    self.puavoId&.to_s
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

    filter = '(&' \
      '(|(objectClass=puavoSchool)(objectClass=puavoEduGroup))' \
      "(cn=#{Net::LDAP::Filter.escape(self.cn)})" \
      ')'

    group_ids = BaseGroup.search_as_utf8(filter: filter, scope: :sub).map { |u| u.last['puavoId'].first }

    group_ids.delete_if { |id| self.puavoId.to_i == id.to_i } if self.puavoId

    if self.cn.empty? || !group_ids.empty?
      errors.add :cn, I18n.t('activeldap.errors.messages.taken',
                             attribute: I18n.t("activeldap.attributes.#{self.class.to_s.downcase}.cn"))
    end
  end
end
