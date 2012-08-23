require 'spec_helper'
require 'acl_helper'


describe "ACL" do


  env = LDAPTestEnv.new

  env.define :new_admin do |config|
    admin = User.create!(
      :puavoSchool => env.school.dn,
      :givenName => "Gilderoy",
      :sn => "Lockhart",
      :uid => "gilderoy.lockhart",
      :role_name => "Staff",
      :new_password => config.default_password,
      :new_password_confirmation => config.default_password,
      :puavoEduPersonAffiliation => "admin"
    )
    config.dn = admin.dn
  end


  describe "school" do

    before(:all) { env.reset }
    school_attributes = [
      :cn,
      :displayName,
      :gidNumber,
      :member,
      :memberUid,
      :objectClass,
      :puavoId,
      :puavoSchoolAdmin,
      :sambaGroupType,
      :sambaSID,
    ]

    it "should enforce basic school permissions" do
      env.admin.can_read :school, school_attributes
      env.student.can_read :school, school_attributes
      env.teacher.can_read :school, school_attributes

      env.owner.can_modify :school, [ :replace, :displayName, ["Test school"] ]
      env.owner.can_modify :school, [ :replace, :puavoSchoolAdmin, [env.new_admin.dn] ]

      env.student.cannot_modify :school, [ :replace, :displayName, ["newname"] ], InsufficientAccessRights
      env.admin.cannot_modify :school, [ :replace, :puavoSchoolAdmin, [env.student.dn] ], InsufficientAccessRights
    end
  end

end
