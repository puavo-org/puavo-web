
module PuavoRest

class LegacyRole < LdapModel
  ldap_map :dn, :dn
  ldap_map :puavoId, :id
  ldap_map :cn, :abbreviation
  ldap_map :displayName, :name
  ldap_map :puavoSchool, :school_dn
  ldap_map :memberUid, :member_usernames, LdapConverters::ArrayValue

  def self.ldap_base
    "ou=Roles,#{ organisation["base"] }"
  end

end

class LegacyRoles < LdapSinatra

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
    School.by_id!(params["school_id"])

    role = LegacyRole.by_id!(params["role_id"])
    role.add!(:member_usernames, params["username"])
    role
  end

end
end
