class School < BaseGroup
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
  
  validates_format_of( :cn,
                       :with => /^[a-z0-9-]+$/,
                       :message => I18n.t("activeldap.errors.messages.school.invalid_characters",
                                          :attribute => I18n.t("activeldap.attributes.school.cn")) )

  validates_format_of( :puavoNamePrefix,
                       :allow_blank => true,
                       :with => /^[a-z0-9-]+$/,
                       :message => I18n.t("activeldap.errors.messages.school.invalid_characters",
                                          :attribute => I18n.t("activeldap.attributes.school.puavoNamePrefix")) )

  def remove_user(user)
    self.ldap_modify_operation(:delete, [{ "memberUid" => [user.uid]},
                                         { "member" => [user.dn.to_s] }])

    if Array(user.puavoAdminOfSchool).map{ |s| s.to_s }.include?(self.dn.to_s)
      self.ldap_modify_operation(:delete, [{ "puavoSchoolAdmin" => [user.dn.to_s] }])
    end
  end

  def self.all_with_permissions
    if Puavo::Authorization.organisation_owner?
      self.all.sort
    else
      self.find(:all, :attribute => "puavoSchoolAdmin", :value => Puavo::Authorization.current_user.dn).sort
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

  private

  def resize_image
    if self.image.class == Tempfile
      image_orig = Magick::Image.read(self.image.path).first
      self.jpegPhoto = image_orig.resize_to_fit(400,200).to_blob
    end
  end
end
