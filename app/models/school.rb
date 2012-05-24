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
  
  def validate
    unless self.cn.to_s =~ /^[a-z0-9-]+$/
      errors.add( :cn, I18n.t("activeldap.errors.messages.school.invalid_characters",
                              :attribute => I18n.t("activeldap.attributes.school.cn")) )
    end
    unless self.puavoNamePrefix.to_s =~ /^[a-z0-9-]*$/
      errors.add( :puavoNamePrefix, I18n.t("activeldap.errors.messages.school.invalid_characters",
                                           :attribute => I18n.t("activeldap.attributes.school.puavoNamePrefix")) )
    end
  end

  def remove_user(user)
    self.ldap_modify_operation(:delete, [{ "memberUid" => [user.uid]},
                                         { "member" => [user.dn.to_s] }])

    if Array(user.puavoAdminOfSchool).map{ |s| s.to_s }.include?(self.dn.to_s)
      self.ldap_modify_operation(:delete, [{ "puavoSchoolAdmin" => [user.dn.to_s] }])
    end
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

  def to_json(*args)
    { "group_name" => self.cn,
      "state" => self.st,
      "postal_address" => self.postalAddress,
      "phone_number" => self.telephoneNumber,
      "gid" => self.gidNumber,
      "name" => self.displayName,
      "street" => self.street,
      "puavo_id" => self.puavoId,
      "postal_code" => self.postalCode,
      "home_page" => self.puavoSchoolHomePageURL,
      "samba_SID" => self.sambaSID,
      "samba_group_type" => self.sambaGroupType,
      "post_office_box" => self.postOfficeBox }.to_json
  end

  private

  def resize_image
    if self.image.class == Tempfile
      image_orig = Magick::Image.read(self.image.path).first
      self.jpegPhoto = image_orig.resize_to_fit(400,200).to_blob
    end
  end
end
