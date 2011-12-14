class School < BaseGroup
  ldap_mapping( :dn_attribute => "puavoId",
                :prefix => "ou=Schools,ou=Groups",
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

  has_many( :roles, :class_name => "SchoolRole",
            :primary_key => 'dn',
            :foreign_key => 'puavoSchool' )

  has_many( :groups, :class_name => 'StudentYearClass',
            :primary_key => 'dn',
            :foreign_key => 'puavoSchool' )

  attr_accessor :image
  before_validation :resize_image
  after_save :create_or_update_school_roles
  
  def validate
    unless self.cn.to_s =~ /^[a-z0-9-]+$/
      errors.add( :cn, I18n.t("activeldap.errors.messages.school.invalid_characters",
                              :attribute => I18n.t("activeldap.attributes.school.cn")) )
    end
    # man groupadd (linux):
    # Groupnames may only be up to 32 characters long.
    # 
    # School's cn value is prefix for the other groups name.
    # Set max length (14 characters) on cn
    if self.cn.to_s.length > 14
      errors.add( :cn, I18n.t("activeldap.errors.messages.too_long",
                              :attribute => I18n.t("activeldap.attributes.student_year_class.cn"),
                              :count => 14) )
    end
    unless self.puavoNamePrefix.to_s =~ /^[a-z0-9-]*$/
      errors.add( :puavoNamePrefix, I18n.t("activeldap.errors.messages.school.invalid_characters",
                                           :attribute => I18n.t("activeldap.attributes.school.puavoNamePrefix")) )
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

  def create_or_update_school_roles
    roles = Role.base_search
    school_roles_by_organisation = []
    roles.each do |role|
      school_roles_by_organisation.push( { :cn => self.cn + "-" + role[:cn],
                                           :displayName => role[:displayName],
                                           :puavoEduPersonAffiliation => role[:puavoEduPersonAffiliation],
                                           :puavoSchool => self.dn.to_s,
                                           :puavoUserRole => role[:dn] } )
    end
    school_roles = SchoolRole.base_search( :filter => "puavoSchool=#{self.dn}",
                                           :attributes => ['cn', 'displayName',
                                                           'puavoEduPersonAffiliation',
                                                           'puavoSchool', 'puavoUserRole'] )
    school_roles_by_organisation.each do |role|
      if (school_role = school_roles.select{ |r| r[:puavoUserRole] == role[:puavoUserRole] }.first).nil?
        SchoolRole.create(role)
      else
        school_role_puavo_id = school_role.delete(:puavoId)
        school_role_dn = school_role.delete(:dn)
        unless role.diff(school_role).empty?
          school_role_object = SchoolRole.find(school_role_dn)
          school_role_object.update_attributes(role)
        end
      end
    end
  end

  def resize_image
    if self.image.class == Tempfile
      image_orig = Magick::Image.read(self.image.path).first
      self.jpegPhoto = image_orig.resize_to_fit(400,200).to_blob
    end
  end
end
