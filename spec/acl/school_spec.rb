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

    it "should allow admins to read school attributes" do
      env.admin.can_read :school, [:puavoId,
                                   :objectClass,
                                   :gidNumber,
                                   :displayName,
                                   :sambaSID,
                                   :cn,
                                   :sambaGroupType,
                                   :memberUid,
                                   :member,
                                   :puavoSchoolAdmin ]
    end


    it "should not allow admins to write school puavoSchoolAdmin attribute" do
      lambda {
        env.admin.can_modify :school, [ :replace, :puavoSchoolAdmin, [env.student.dn] ]
      }.should raise_error InsufficientAccessRights

    end

    it "should allow owner to write school attributes" do
      env.owner.can_modify :school, [ :replace, :displayName, ["Test school"] ]
    end

    it "should allow owner to write school puavoSchoolAdmin attribute" do
      env.owner.can_modify :school, [ :replace, :puavoSchoolAdmin, [env.new_admin.dn] ]
    end

    it "should not allow student to change school attributes" do
      lambda {
        env.student.can_modify :school, [ :replace, :displayName, ["newname"] ]
      }.should raise_error InsufficientAccessRights
    end

  end

end
