class Group < BaseGroup
  ldap_mapping( :dn_attribute => "puavoId",
                :prefix => "ou=Groups",
                :classes => ['top', 'posixGroup', 'puavoEduGroup','sambaGroupMapping'] )
  has_many :members, :class_name => "User", :wrap => "member", :primary_key => "dn"
  has_many :memberUids, :class_name => "User", :wrap => "memberUid", :primary_key => "uid"
  has_many :primary_members, :class_name => 'User', :foreign_key => 'gidNumber', :primary_key => 'gidNumber'

  belongs_to( :school, :class_name => 'School',
              :foreign_key => 'puavoSchool',
              :primary_key => 'dn' )

  belongs_to( :roles,
              :class_name => "Role",
              :many => "puavoMemberGroup",
              :primary_key => "dn" )

  validates_presence_of( :displayName,
                         :message => I18n.t("activeldap.errors.messages.blank",
                                                :attribute => I18n.t("activeldap.attributes.group.displayName") ) )

  def to_s
    self.displayName
  end
  
  def remove_user(user)
    self.ldap_modify_operation(:delete, [{ "memberUid" => [user.uid]},
                                         { "member" => [user.dn.to_s] }])
  end
end

