class Group < BaseGroup
  include HasPrinterMixin
  ldap_mapping( :dn_attribute => "puavoId",
                :prefix => "ou=Groups",
                :classes => ['top', 'posixGroup', 'puavoEduGroup','sambaGroupMapping'] )
  has_many :members, :class_name => "User", :wrap => "member", :primary_key => "dn"
  has_many :memberUids, :class_name => "User", :wrap => "memberUid", :primary_key => "uid"
  has_many :primary_members, :class_name => 'User', :foreign_key => 'gidNumber', :primary_key => 'gidNumber'

  belongs_to( :school, :class_name => 'School',
              :foreign_key => 'puavoSchool',
              :primary_key => 'dn' )

  validate :validate

  def validate
    unless self.cn.to_s =~ /^[a-z0-9-]+$/
      errors.add( :cn, I18n.t("activeldap.errors.messages.group.invalid_characters") )
    end
    if self.displayName.to_s.empty?
      errors.add( :displayName, I18n.t("activeldap.errors.messages.blank",
                                       :attribute => I18n.t("activeldap.attributes.group.displayName")) )
    end
  end

  def to_s
    self.displayName
  end

  def add_user(user)
    # Do both adds separately, in case the association was only partial.
    # Oh how I miss actual SQL relations and transactions...
    begin
      self.ldap_modify_operation(:add, [{ "memberUid" => [user.uid]}])
    rescue ActiveLdap::LdapError::TypeOrValueExists
    end

    begin
      self.ldap_modify_operation(:add, [{ "member" => [user.dn.to_s] }])
    rescue ActiveLdap::LdapError::TypeOrValueExists
    end
  end

  def remove_user(user)
    # Do both removals separately, in case the association was only partial.
    # Oh how I miss actual SQL relations and transactions...
    begin
      self.ldap_modify_operation(:delete, [{ "memberUid" => [user.uid] }])
    rescue ActiveLdap::LdapError::NoSuchAttribute
    end

    begin
      self.ldap_modify_operation(:delete, [{ "member" => [user.dn.to_s] }])
    rescue ActiveLdap::LdapError::NoSuchAttribute
    end
  end

  def as_json(*args)
    { "school_id" => self.school.puavoId,
      "abbreviation" => self.cn.to_s,
      "gid" => self.gidNumber,
      "name" => self.displayName,
      "puavo_id" => self.puavoId,
      "samba_SID" => self.sambaSID,
      "samba_group_type" => self.sambaGroupType }
  end

  def member?(user_id)
    self.members.map{ |u| u.puavoId }.include?(user_id.to_i)
  end
end

