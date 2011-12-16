class Role < BaseGroup
  ldap_mapping( :dn_attribute => "puavoId",
                :prefix => "ou=Roles,ou=Groups",
                :classes => ['top', 'posixGroup', 'puavoRole', 'sambaGroupMapping'] )

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
  after_save :create_or_update_role_to_schools

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

  private

  def create_or_update_role_to_schools
    schools = School.base_search(:attributes => ['cn'])
    schools.each do |school|
      new_school_role = { 
        :cn => school[:cn] + "-" + self.cn,
        :displayName => self.displayName,
        :puavoEduPersonAffiliation => self.puavoEduPersonAffiliation,
        :puavoSchool => school[:dn],
        :puavoRole => self.dn.to_s }
      if ( school_role = SchoolRole.base_search(:filter => "&(puavoRole=#{self.dn})" +
                                                           "(puavoSchool=#{school[:dn]})", 
                                                :attributes => ['cn', 'displayName',
                                                                'puavoEduPersonAffiliation',
                                                                'puavoSchool', 'puavoRole']).first ).nil?
        SchoolRole.create(new_school_role)
      else
        school_role_puavo_id = school_role.delete(:puavoId)
        school_role_dn = school_role.delete(:dn)
        unless new_school_role.diff(school_role).empty?
          school_role_object = SchoolRole.find(dn)
          school_role_object.update_attributes(new_school_role)
        end
      end
    end
  end
end
