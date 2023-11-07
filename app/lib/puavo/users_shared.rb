# Shared stuff between UsersController and UserMassOperationsController

module Puavo
  module UsersShared
    # Removes the user from the target school. Assumes you've done the prerequisite verifications
    # (the user is in the school and it's not the user's primary school).
    # TODO: Why isn't this part of the User model?
    def self.remove_user_from_school(user, school)
      schools = Array(user.puavoSchool.dup)
      schools.reject! { |s| s.to_s == school.dn.to_s }
      user.puavoSchool = (schools.count == 1) ? schools[0] : schools

      # Remove school admin associations if needed
      Array(user.puavoAdminOfSchool).each do |dn|
        if dn.to_s == school.dn.to_s
          user.puavoAdminOfSchool = Array(user.puavoAdminOfSchool).reject { |dn| dn.to_s == school.dn.to_s }
          school.puavoSchoolAdmin = Array(school.puavoSchoolAdmin).reject { |dn| dn.to_s == user.dn.to_s }
          school.save!
          break
        end
      end

      # This must be done first, otherwise ldap_modify_operation() below will fail
      user.save!

      # The system appears to automatically add the user's UID and DN to the relevant arrays,
      # but it won't *remove* them
      begin
        LdapBase.ldap_modify_operation(school.dn, :delete, [{ "member" => [user.dn.to_s] }])
      rescue ActiveLdap::LdapError::NoSuchAttribute
      end

      begin
        LdapBase.ldap_modify_operation(school.dn, :delete, [{ "memberUid" => [user.uid.to_s] }])
      rescue ActiveLdap::LdapError::NoSuchAttribute
      end
    end
  end
end
