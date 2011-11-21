class Role < LdapBase
  ldap_mapping( :dn_attribute => "puavoId",
                :prefix => "ou=Roles,ou=Groups",
                :classes => ['top',  'puavoUserRole'] )

  has_many :members, :class_name => "User", :wrap => "member", :primary_key => "dn"
  has_many :memberUids, :class_name => "User", :wrap => "memberUid", :primary_key => "uid"

  has_many( :groups,
            :class_name => "Group",
            :wrap => "puavoMemberGroup",
            :primary_key => "dn" )
            

  belongs_to( :school, :class_name => 'School',
              :foreign_key => 'puavoSchool',
              :primary_key => 'dn' )

  before_validation :set_special_ldap_value

  def validate
    if self.displayName.to_s.empty?
      errors.add( :displayName, I18n.t("activeldap.errors.messages.blank",
                                       :attribute => I18n.t("activeldap.attributes.role.displayName")) )
    end
  end

  def set_special_ldap_value
    self.puavoId = IdPool.next_puavo_id if self.puavoId.nil?
  end

  def id
    self.puavoId.to_s unless puavoId.nil?
  end

  def add_member(member)
    unless Array(self.member).include?(member.dn)
      self.member = Array(self.member).push member.dn
    end
    unless Array(self.memberUid).include?(member.uid)
      self.memberUid = Array(self.memberUid).push member.uid
    end
    self.save
  end

  def delete_member(member)
    attributes = [ {'member' => [member.dn.to_s]},
                   {'memberUid' => [member.uid.to_s]} ]
    self.ldap_modify_operation(:delete, attributes)
  end
end
