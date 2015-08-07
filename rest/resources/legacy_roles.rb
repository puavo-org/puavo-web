
module PuavoRest

class LegacyRole < LdapModel
  ldap_map :dn, :dn
  ldap_map :puavoId, :id
  ldap_map :cn, :abbreviation
  ldap_map :displayName, :name
  ldap_map :puavoSchool, :school_dn
  ldap_map :memberUid, :member_usernames, LdapConverters::ArrayValue
  ldap_map :member, :member_dns, LdapConverters::ArrayValue

  def self.ldap_base
    "ou=Roles,#{ organisation["base"] }"
  end

  # Add member to role. Append username to `memberUid` and dn to `member` ldap
  # attributes
  #
  # @param user [User] user to add as member
  def add_member(user)
    add(:member_usernames, user.username)
    add(:member_dns, user.dn)
  end

  # Remove member for the role
  #
  # @param user [User] user to add as member
  def remove_member(user)
    remove(:member_usernames, user.username)
    remove(:member_dns, user.dn)
  end

end

class LegacyRoles < PuavoSinatra

  get "/v3/schools/:school_id/legacy_roles" do
    auth :basic_auth, :kerberos
    school =  School.by_id!(params["school_id"])
    legacy_roles = LegacyRole.by_attr!(:school_dn, school.dn, :multi)
    json legacy_roles
  end

  get "/v3/schools/:school_id/legacy_roles/:role_id" do
    auth :basic_auth, :kerberos

    # Just assert that the school in the url exists
    School.by_id!(params["school_id"])

    json LegacyRole.by_id!(params["role_id"])
  end

  post "/v3/schools/:school_id/legacy_roles/:role_id/members" do
    auth :basic_auth, :kerberos

    # Just assert that the school in the url exists
    school = School.by_id!(params["school_id"])
    user = User.by_username!(params["username"])
    role = LegacyRole.by_id!(params["role_id"])

    if role.school_dn != school.dn
      raise BadInput, :user => "the role does not belog to the school"
    end

    role.add_member(user)
    role.save!
    json role
  end

end
end
