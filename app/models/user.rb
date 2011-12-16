# -*- coding: utf-8 -*-
class User < LdapBase
  # When using user mass import we have to store uids which are already been taken. See validate method.
  @@reserved_uids = Array.new

  include Puavo::Authentication

  # Raised by change_ldap_password method when password cannot be changed.
  # Example this happens when kerberos servers is down.
  class PasswordChangeFailed < UserError
  end

  ldap_mapping( :dn_attribute => "puavoId",
                :prefix => "ou=People",
                :classes => ['top', 'posixAccount', 'inetOrgPerson', 'puavoEduPerson','sambaSamAccount','eduPerson'] )
  belongs_to :uidGroups, :class_name => 'Group', :many => 'memberUid', :primary_key => "Uid"
  belongs_to( :school, :class_name => 'School',
              :foreign_key => 'puavoSchool',
              :primary_key => 'dn' )
  belongs_to :member_school, :class_name => 'School', :many => 'member', :primary_key => "dn"
  belongs_to :member_uid_school, :class_name => 'School', :many => 'memberUid', :primary_key => "uid"
  belongs_to :uidRoles, :class_name => 'Role', :many => 'memberUid', :primary_key => "uid"

  before_validation :set_special_ldap_value, :resize_image

  before_save :is_uid_changed

  before_update :change_ldap_password

  after_save :update_student_class
  after_save :add_member_uid_to_models
  after_save :update_roles

  before_destroy :delete_all_associations

  after_create :change_ldap_password

  # role_ids/role_name: see set_role_ids_by_role_name and validate methods
  attr_accessor( :password,
                 :new_password,
                 :school_admin,
                 :uid_has_changed,
                 :role_ids,
                 :role_name,
                 :mass_import,
                 :image,
                 :earlier_user,
                 :new_password_confirmation,
                 :student_class,
                 :student_class_id )

  cattr_accessor :reserved_uids

  OVERWRITE_CHARACTERS = {
    "Ä" => "a",
    "ä" => "a",
    "Ö" => "o",
    "ö" => "o",
    "Å" => "a",
    "å" => "a",
    "é" => "e"
  }

  def to_json(*args)
    self.class.build_hash_for_to_json(self).to_json
  end
  
  # Building hash for to_json method with better name of attributes
  #  * data argument may be User or Hash
  def self.build_hash_for_to_json(data)
    new_user_hash = {}
    # Note: value of attribute may be raw ldap value eg. { givenName => ["Joe"] }
    user_attributes =
      [ { :original_attribute_name => "givenName",
          :new_attribute_name => "given_name",
          :value_block => lambda{ |value| Array(value).first } },
        { :original_attribute_name => "puavoAdminOfSchool",
          :new_attribute_name => "admin_of_schools",
          :value_block => lambda{ |value| value ? Array(value).map{ |s| s.to_s.match(/puavoId=([^, ]+)/)[1].to_i } : [] } },
        { :original_attribute_name => "puavoSchool",
          :new_attribute_name => "school_id",
          :value_block => lambda{ |value| value.to_s.match(/puavoId=([^, ]+)/)[1].to_i } },
        { :original_attribute_name => "telephoneNumber",
          :new_attribute_name => "telephone_number",
          :value_block => lambda{ |value| Array(value).first } },
        { :original_attribute_name => "displayName",
          :new_attribute_name => "name",
          :value_block => lambda{ |value| Array(value).first } },
        { :original_attribute_name => "gidNumber",
          :new_attribute_name => "gid",
          :value_block => lambda{ |value| Array(value).first.to_i } },
        { :original_attribute_name => "homeDirectory",
          :new_attribute_name => "home_directory",
          :value_block => lambda{ |value| Array(value).first } },
        { :original_attribute_name => "puavoEduPersonAffiliation",
          :new_attribute_name => "user_type",
          :value_block => lambda{ |value| Array(value).first } },
        { :original_attribute_name => "mail",
          :new_attribute_name => "email",
          :value_block => lambda{ |value| Array(value).first } },
        { :original_attribute_name => "puavoEduPersonReverseDisplayName",
          :new_attribute_name => "reverse_name",
          :value_block => lambda{ |value| Array(value).first } },
        { :original_attribute_name => "sn",
          :new_attribute_name => "surname",
          :value_block => lambda{ |value| Array(value).first } },
        { :original_attribute_name => "uid",
          :new_attribute_name => "uid",
          :value_block => lambda{ |value| Array(value).first } },
        { :original_attribute_name => "puavoId",
          :new_attribute_name => "puavo_id",
          :value_block => lambda{ |value| Array(value).first.to_i } },
        { :original_attribute_name => "sambaSID",
          :new_attribute_name => "samba_sid",
          :value_block => lambda{ |value| Array(value).first } },
        { :original_attribute_name => "uidNumber",
          :new_attribute_name => "uid_number",
          :value_block => lambda{ |value| Array(value).first.to_i } },
        { :original_attribute_name => "loginShell",
          :new_attribute_name => "login_shell",
          :value_block => lambda{ |value| Array(value).first } },
        { :original_attribute_name => "sambaPrimaryGroupSID",
          :new_attribute_name => "samba_primary_group_SID",
          :value_block => lambda{ |value| Array(value).first } } ]
    
    user_attributes.each do |attr|
      attribute_value = data.class == Hash ? data[attr[:original_attribute_name]] : data.send(attr[:original_attribute_name])
      new_user_hash[attr[:new_attribute_name]] = attr[:value_block].call(attribute_value)
    end
    return new_user_hash
  end

  def validate
    # Uid validation
    #
    # Password confirmation
    if !self.new_password_confirmation.nil? && self.new_password != self.new_password_confirmation
      errors.add( :new_password, I18n.t("activeldap.errors.messages.confirmation",
                                        :attribute => I18n.t("activeldap.attributes.user.new_password")) )
    end

    # Validates length of uid
    if self.uid.to_s.size < 3
      errors.add( :uid,  I18n.t("activeldap.errors.messages.too_short",
                                :attribute => I18n.t("activeldap.attributes.user.uid"),
                                :count => 3) )
    end
    if self.uid.to_s.size > 255
      errors.add( :uid, I18n.t("activeldap.errors.messages.too_long",
                               :attribute => I18n.t("activeldap.attributes.user.uid"),
                               :count => 255) )
    end
    # Format of uid, default configuration:
    #   * allowed characters is a-z0-9.-
    #   * uid must begin with the small letter
    allow_upprecase_characters_uid = Puavo::Organisation.
      find(LdapOrganisation.current.cn).
      value_by_key("allow_uppercase_characters_uid").
      to_s.chomp == "true" ? true : false rescue false

    unless self.uid.to_s =~ ( allow_upprecase_characters_uid ? /^[a-zA-Z]/ : /^[a-z]/ )
      errors.add( :uid, I18n.t("activeldap.errors.messages.user.must_begin_with") )
    end
    unless self.uid.to_s =~ ( allow_upprecase_characters_uid ? /^[a-zA-Z0-9.-]+$/ : /^[a-z0-9.-]+$/ )
      errors.add( :uid, I18n.t("activeldap.errors.messages.user.invalid_characters") )
    end

    # Role validation
    #
    # The user must have at least one role
    #
    # Set role_ids value by role_name. If get false role_name is invalid.
    # FIXME
    # if set_role_ids_by_role_name(role_name) == false
    #   errors.add( :role_name,
    #               I18n.t("activeldap.errors.messages.invalid",
    #                      :attribute => I18n.t("activeldap.attributes.user.role_name") ) )
    #
    # If role_ids is nil: user's role associations not change when save object. Then roles must not be empty!
    # If role_ids is not nil: user's roles value will change when save object. Then role_ids must not be empty!
    if (!role_ids.nil? && role_ids.empty?) || ( role_ids.nil? && self.roles.empty? )
      errors.add_on_blank :role_ids, I18n.t("activeldap.errors.messages.blank",
                                         :attribute => I18n.t("activeldap.attributes.user.roles") )
    else
      # Role must be found by id!
      unless role_ids.nil?
        role_ids.each do |id|
          if SchoolRole.find(:first, id).nil?
            errors.add_on_blank :role_ids, I18n.t("activeldap.errors.messages.blank",
                                                  :attribute => I18n.t("activeldap.attributes.user.role_ids") )
          end
        end
      end
    end

    # uid validation
    if user = User.find(:first, :attribute => "uid", :value => self.uid)
      if user.puavoId != self.puavoId
        self.earlier_user = user
        errors.add :uid, I18n.t("activeldap.errors.messages.taken",
                                :attribute => I18n.t("activeldap.attributes.user.uid") )
      end
    end

    # mass import uid validation
    if self.mass_import
      if @@reserved_uids.include?(self.uid)
        errors.add :uid, I18n.t("activeldap.errors.messages.taken",
                                :attribute => I18n.t("activeldap.attributes.user.uid") )
      end
    end

    # Student class validation
    # Student class must be selected if the user belongs to the Student role
    student_school_role = SchoolRole.base_search( :filter => "(puavoEduPersonAffiliation=student)" +
                                                  "(puavoSchool=#{self.school.dn})" ).first
    if self.role_ids.include?( student_school_role[:puavoId].to_s )
      if self.student_class_id.empty?
        errors.add_on_blank( :student_class_id,
                             I18n.t("activeldap.errors.messages.blank",
                                    :attribute => I18n.t("activeldap.attributes.user.student_class_id") ) )
      end
    end
  end

  def change_ldap_password
    unless new_password.nil? || new_password.empty?
      ldap_conf = User.configuration
      system( 'ldappasswd', '-Z',
              '-h', ldap_conf[:host],
              '-D', ldap_conf[:bind_dn],
              '-w', ldap_conf[:password],
              '-s', new_password,
              dn.to_s )
      if $?.exitstatus != 0
        raise PasswordChangeFailed, I18n.t('flash.password.failed')
      end
    end
  end

  def self.import_columns
    ["givenName", "sn", "uid", "new_password", "role_name", "puavoEduPersonAffiliation"]
  end

  # FIXME, where is better location on this method? Using same code also on other model?
  def self.human_attribute_name(*args)
    if I18n.t("activeldap.attributes").has_key?(:user) &&
       # Attribute key name
       I18n.t("activeldap.attributes.user").has_key?(args[0].to_sym)
      return I18n.t("activeldap.attributes.user.#{args[0]}")
    end
    super(*args)
  end

  #
  # Retruns the array (users). 
  #
  # Example of Data: {"0"=>["Wilk", "Mabey"], "1"=>["Ben", "Joseph"], "2"=>["Class 4", "Class 4"]}
  # Example of Columns: {"0" => "Lastname", "1" => "Given names", "2" => "Group" }
  # 
  def self.hash_array_data_to_user(data, columns, school)
    users = []
    max_data_column_number = (columns.count - 1).to_s
    # Row contains one user data (row number == user_index)
    0.upto data["0"].length-1 do |user_index|
      next if Array(data[ (max_data_column_number.to_i + 1).to_s ]).include?(user_index.to_s)
      user = Hash.new
      0.upto max_data_column_number.to_i do |column_index|
        unless columns[column_index].nil?
          user[columns[column_index]] = data[column_index.to_s][user_index]
        end
      end
      new_user = User.new(user)
      new_user.puavoSchool = school.dn
      new_user.mass_import = true
      if data[(max_data_column_number.to_i + 1).to_s] && data[(max_data_column_number.to_i + 1).to_s][user_index.to_s]
        new_user.earlier_user = User.find(data[(max_data_column_number.to_i + 1).to_s][user_index.to_s])
      end
      users.push new_user
    end

    return users
  end

  def self.validate_users(users)
    valid = []
    invalid = []
    User.reserved_uids = []

    users.each do |user|
      if  user.uid.nil? or user.uid.empty?
        user.generate_username
      end
      if user.puavoId.nil?
        user.puavoId = "0"
      end
      user.valid? ? (valid.push user) : (invalid.push user)
      User.reserved_uids.push user.uid
    end
    return valid, invalid
  end

  #
  # Return array. This array includes arrays of users, one per role
  #
  def self.list_by_role(users)
    users_by_role = []
    roles_by_name = users.map {|user| user.roles.first.displayName}.uniq
    roles_by_name.each do |role_name|
      users_by_role.push users.select {|u| u.roles.first.displayName == role_name}
    end
    return users_by_role
  end
  def generate_password
    characters = (("a".."z").to_a + ("0".."9").to_a).delete_if do |char| not char[/[015iIosq]/].nil? end
    self.new_password = Array.new(8) { characters[rand(characters.size)] }.join
  end

  def self.puavoEduPersonAffiliation_list
    ["teacher", "staff", "student", "visitor", "parent", "admin", "testuser"]
  end

  def id
    self.puavoId.to_s unless self.puavoId.nil?
  end

  # Update user's role list by role_ids
  def update_roles
    unless self.role_ids.nil?
      add_roles = self.role_ids
      SchoolRole.base_search( :filter => "member=#{self.dn}",
                              :attributes => ['puavoId',
                                              'puavoEduPersonAffiliation',
                                              'puavoUserRole'] ).each do |role|
        if add_roles.include?(role[:puavoId])
          add_roles.delete(role[:puavoId])
        else
          SchoolRole.ldap_modify_operation(role[:dn],
                                           :delete, [{ "memberUid" => [self.uid] }]
                                           ) rescue Exception
          SchoolRole.ldap_modify_operation(role[:dn],
                                           :delete, [{ "member" => [self.dn.to_s] }]
                                           ) rescue Exception
          SchoolRole.ldap_modify_operation(role[:puavoUserRole],
                                           :delete, [{ "memberUid" => [self.uid] }]
                                           ) rescue Exception
          SchoolRole.ldap_modify_operation(role[:puavoUserRole],
                                           :delete, [{ "member" => [self.dn.to_s] }]
                                           ) rescue Exception
          User.ldap_modify_operation( self.dn,
                                      :delete,
                                      [{ "puavoEduPersonAffiliation" => [role[:puavoEduPersonAffiliation]] }]) 
        end
      end
      
      # Add roles
      add_roles.each do |role_id|
        role = SchoolRole.base_search( :filter => "puavoId=#{role_id}",
                                       :attributes => ['puavoId',
                                                       'puavoUserRole',
                                                       'puavoEduPersonAffiliation'] ).first
        User.ldap_modify_operation( self.dn,
                                    :add, [{ "puavoEduPersonAffiliation" => [role[:puavoEduPersonAffiliation]] }]) 
        SchoolRole.ldap_modify_operation(role[:dn],
                                         :add, [{ "memberUid" => [self.uid] }, 
                                                { "member" => [self.dn.to_s] }]
                                         ) rescue ActiveLdap::LdapError::TypeOrValueExists
        Role.ldap_modify_operation(role[:puavoUserRole],
                                   :add, [{ "memberUid" => [self.uid] }, 
                                          { "member" => [self.dn.to_s] }]
                                   ) rescue ActiveLdap::LdapError::TypeOrValueExists
      end
    end
  end


  def generate_username
    self.uid = username_escape(self.givenName).to_s + "." + username_escape(self.sn).to_s
  end

  def username_escape(string)
    string.strip.split(//).map do |char|
      OVERWRITE_CHARACTERS.has_key?(char) ? OVERWRITE_CHARACTERS[char] : char
    end.join.downcase.gsub(/[^a-z]/, '')
  end

  def human_readable_format(attribute)
    case attribute
    when "role_ids"
      self.send(attribute).map do |id|
        Role.find(id).displayName
      end
    when "puavoEduPersonAffiliation"
      if self.class.puavoEduPersonAffiliation_list.include?(self.send(attribute).to_s)
        I18n.t( 'puavoEduPersonAffiliation_' + self.send(attribute) )
      else
        self.send(attribute).to_s
      end
    else
      self.send(attribute).to_s
    end
  end

  def change_school(new_school_dn)
    school_dn = self.puavoSchool
    LdapBase.ldap_modify_operation( self.puavoSchool,
                                    :delete, [{ "memberUid" => [self.uid.to_s],
                                                "member" => [self.dn.to_s] }])
    self.puavoSchool = new_school_dn
  end

  def student_class
    @student_class || ( self.puavoId.nil? ?
                        nil :
                        @student_class = StudentYearClass.find_first_by_member(self.dn.to_s) )
  end

  def student_class_id
    @student_class_id || ( self.student_class.nil? ? nil : self.student_class.puavoId.to_s)
  end

  def roles
    SchoolRole.find( :all,
                     :attribute => "member",
                     :value => self.dn.to_s )
  end

  private

  # Find role object by name (role_name) and set id to role_ids array.
  #
  # set_role_ids_by_role_name method is run when validate object (see "validate" method).
  #
  # update_roles method run after save. update_roles join roles to user by role id (role_ids).
  #
  # This makes it possible for that you can also set user's role by name.
  # user = User.first
  # user.role_name = "Administrator"
  # user.save
  def set_role_ids_by_role_name(name)
    unless role_name.nil?
      role = Role.find( :all,
                        :attribute => "displayName",
                        :value => name).delete_if{ |r| r.puavoSchool != self.puavoSchool }.first
      if role.nil?
        return false
      else
        self.role_ids = Array(role.id)
      end
    end
    return true
  end

  def set_special_ldap_value
    self.displayName = self.givenName + " " + self.sn
    self.cn = self.uid
    self.homeDirectory = "/home/" + self.school.cn + "/" + self.uid unless self.uid.nil?
    self.gidNumber = self.school.gidNumber unless self.puavoSchool.nil?
    set_uid_number if self.uidNumber.nil?
    self.puavoId = IdPool.next_puavo_id if self.puavoId.nil?
    set_samba_settings if self.sambaSID.nil?
    unless self.gidNumber.nil? || self.puavoSchool.nil?
      self.sambaPrimaryGroupSID = "#{SambaDomain.first.sambaSID}-#{self.school.puavoId}"
    end
    self.loginShell = '/bin/bash'
    self.eduPersonPrincipalName = "#{self.uid}@#{LdapOrganisation.current.puavoKerberosRealm}"
    if self.puavoAllowRemoteAccess.class == String
      self.puavoAllowRemoteAccess = case self.puavoAllowRemoteAccess
                                    when "true"
                                      true
                                    when "false"
                                      false
                                    end
    end
    self.puavoEduPersonReverseDisplayName = self.sn + " " + self.givenName
  end

  def set_uid_number
    self.uidNumber = IdPool.next_uid_number
  end

  def is_uid_changed
    unless self.puavoId.nil?
      begin
        old_user = User.find(self.puavoId)
        if self.uid != old_user.uid
          self.uid_has_changed = true
          logger.debug "User uid has changed. Remove memberUid from roles and groups"
          old_uid = Net::LDAP::Filter.escape(old_user.uid)
          BaseGroup.base_search( :filter => "(memberUid=#{old_uid})",
                                 :scope => :sub,
                                 :attributes => ['puavoId'] ).each do |group|
            begin
              BaseGroup.ldap_modify_operation(group[:dn],
                                              :delete, [{ "memberUid" => [old_uid] }])
            rescue Exception; end
          end
        end
      rescue ActiveLdap::EntryNotFound; end
    end
  end

  def add_member_uid_to_models
    begin
      self.school.ldap_modify_operation( :add, [{"memberUid" => [self.uid.to_s]}] )
    rescue ActiveLdap::LdapError::TypeOrValueExists; end
    begin
      self.school.ldap_modify_operation( :add, [{"member" => [self.dn.to_s]}] )
    rescue ActiveLdap::LdapError::TypeOrValueExists; end
    # Set uid to Domain Users group
    SambaGroup.add_uid_to_memberUid('Domain Users', self.uid)
  end

  private

  def delete_all_associations
    # Remove uid from Domain Users group
    SambaGroup.delete_uid_from_memberUid('Domain Users', self.uid)
    if Array(self.puavoAdminOfSchool).count > 0
      SambaGroup.delete_uid_from_memberUid('Domain Admins', self.uid)
    end

    # Remove users from schools, roles, school roles, student classes and student year classes
    BaseGroup.base_search( :filter => "member=#{self.dn}",
                           :scope => :sub ).each do |group|
      BaseGroup.ldap_modify_operation(group[:dn],
                                      :delete, [{ "memberUid" => [self.uid] }]
                                      ) rescue Exception
      BaseGroup.ldap_modify_operation(group[:dn],
                                      :delete, [{ "member" => [self.dn.to_s] }]
                                      ) rescue Exception

    end
    Array(self.puavoAdminOfSchool).each do |school|
      school.ldap_modify_operation( :delete,
                                    [{ "puavoSchoolAdmin" => [self.dn.to_s] }]
                                    ) rescue Exception
    end
  end

  def set_samba_settings 
    self.sambaSID = SambaDomain.next_samba_sid
    self.sambaAcctFlags = "[U]"
  end

  def resize_image
    if self.image.class == Tempfile
      image_orig = Magick::Image.read(self.image.path).first
      self.jpegPhoto = image_orig.resize_to_fit(120,160).to_blob
    end
  end

  def update_student_class
    unless self.student_class_id.nil?
      if old_student_class = StudentYearClass.find_first_by_member(self.dn.to_s)
        if old_student_class.puavoId.to_s != self.student_class_id
          # Remove user from old student class and student year class
          if old_student_class.class == StudentClass
            StudentYearClass.
              ldap_modify_operation( old_student_class.puavoYearClass.to_s,
                                     :delete, [{ "memberUid" => [self.uid] }] ) rescue Exception
            StudentYearClass.
              ldap_modify_operation( old_student_class.puavoYearClass.to_s,
                                     :delete, [{ "member" => [self.dn.to_s] }] ) rescue Exception
          end
          old_student_class.
            ldap_modify_operation( :delete,
                                   [{ "memberUid" => [self.uid] }] ) rescue Exception
          old_student_class.
            ldap_modify_operation( :delete,
                                   [{ "member" => [self.dn.to_s] }] ) rescue Exception
        end
      end
      unless self.student_class_id.empty?
        # Add user to new student class and student year class
        new_student_class = StudentYearClass.find_by_puavoId(self.student_class_id)
        if new_student_class.class == StudentClass
          begin
            StudentClass.
              ldap_modify_operation(new_student_class.puavoYearClass.to_s,
                                    :add, [{ "memberUid" => [self.uid] }, 
                                           { "member" => [self.dn.to_s] }])
          rescue ActiveLdap::LdapError::TypeOrValueExists; end
        end
        begin
          StudentClass.
            ldap_modify_operation(new_student_class.dn.to_s,
                                  :add, [{ "memberUid" => [self.uid] }, 
                                         { "member" => [self.dn.to_s] }])
        rescue ActiveLdap::LdapError::TypeOrValueExists; end
      end
    end
  end
end

# FIXME: this code have to move to better place.
module ActiveLdap
  module Association
    class BelongsTo < Proxy
      # Overwrite to_s method.
      # Example usage: user.primary_group.to_s, return example: "Class 4"
      def to_s
        # exists?-method load target (example group object) and returns true if found it
        if self.exists?
          return self.target.to_s
        end
        return ""
      end
    end
  end
end
