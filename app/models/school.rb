class School < BaseGroup
  include Wlan
  include Puavo::Client::HashMixin::School

  ldap_mapping( :dn_attribute => "puavoId",
                :prefix => "ou=Groups",
                :classes => ['top','posixGroup','puavoSchool','sambaGroupMapping'] )

  has_many( :members, :class_name => "User",
            :primary_key => 'dn',
            :foreign_key => 'puavoSchool' )
  has_many :user_members, :class_name => "User", :wrap => "member", :primary_key => "dn"
  has_many( :user_school_admins,
            :class_name => 'User',
            :primary_key => 'dn',
            :foreign_key => 'puavoAdminOfSchool' )  
  has_many :user_member_uids, :class_name => "User", :wrap => "memberUid", :primary_key => "uid"

  has_many( :groups, :class_name => 'Group',
            :primary_key => 'dn',
            :foreign_key => 'puavoSchool' )

  has_many( :roles, :class_name => "Role",
            :primary_key => 'dn',
            :foreign_key => 'puavoSchool' )

  attr_accessor :image
  before_validation :resize_image

  validate :validate_group_name, :validate_name_prefix, :validate_name, :validate_wlan_attributes

  alias_method :v1_as_json, :as_json

  def image_size
    { width: 400, height: 200 }
  end

  def validate_name
    if self.displayName.to_s.empty?
      errors.add( :displayName, I18n.t("activeldap.errors.messages.blank",
                                       :attribute => I18n.t("activeldap.attributes.school.displayName")) )
    end
  end
  
  def validate_group_name
    unless self.cn.to_s =~ /^[a-z0-9-]+$/
      errors.add( :cn, I18n.t("activeldap.errors.messages.school.invalid_characters",
                              :attribute => I18n.t("activeldap.attributes.school.cn")) )
    end
  end

  def validate_name_prefix
    unless self.puavoNamePrefix.to_s =~ /^[a-z0-9-]*$/
      errors.add( :puavoNamePrefix, I18n.t("activeldap.errors.messages.school.invalid_characters",
                                           :attribute => I18n.t("activeldap.attributes.school.puavoNamePrefix")) )
    end
  end

  def remove_user(user)
    begin
    self.ldap_modify_operation(:delete, [{ "memberUid" => [user.uid]},
                                         { "member" => [user.dn.to_s] }])
    rescue ActiveLdap::LdapError::NoSuchAttribute
      logger.warn "Cannot remove nonexistent memberUid=#{ user.uid } or member=#{ user.dn.to_s } from #{ displayName }"
    end

    if Array(user.puavoAdminOfSchool).map{ |s| s.to_s }.include?(self.dn.to_s)
      begin
        self.ldap_modify_operation(:delete, [{ "puavoSchoolAdmin" => [user.dn.to_s] }])
      rescue ActiveLdap::LdapError::NoSuchAttribute
        logger.warn "Cannot remove nonexistent puavoSchoolAdmin=#{ user.dn.to_s } from #{ displayName }"
      end

    end
  end

  def add_admin(user)
    return (
      self.ldap_modify_operation( :add, [{"puavoSchoolAdmin" => [user.dn.to_s]}] ) &&
      user.ldap_modify_operation( :add, [{"puavoAdminOfSchool" => [self.dn.to_s]}] ) &&
      SambaGroup.add_uid_to_memberUid('Domain Admins', user.uid)
    )
  end

  def self.all_with_permissions(user)
    if user.organisation_owner?
      self.all.sort
    else
      self.find(:all, :attribute => "puavoSchoolAdmin", :value => user.dn).sort
    end
  end

  # FIXME, Is it better to use human_attribute_name method on the application_helper.rb?
  #def self.human_attribute_name(*args)
  #  if I18n.t("activeldap.attributes").has_key?(:school) &&
  #     # Attribute key name
  #      I18n.t("activeldap.attributes.school").has_key?(args[0].to_sym)
  #    return I18n.t("activeldap.attributes.school.#{args[0]}")
  #  end
  #  super(*args)
  #end

  def as_json(*args)
    return ldap_prettify
  end
end
