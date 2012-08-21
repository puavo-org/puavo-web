require 'spec_helper'
require 'acl_helper'


describe "ACL" do


  env = LDAPTestEnv.new

  env.define :school do |config|

    @school = School.create!(
      :cn => "gryffindor",
      :displayName => "Gryffindor"
    )
    config.dn = @school.dn

    Role.create!(
      :displayName => "Class 4",
      :puavoSchool => @school.dn
    )

    Role.create!(
      :displayName => "Staff",
      :puavoSchool => @school.dn
    )
  end

  env.define :teacher do |config|
    teacher = User.create!(
      :puavoSchool => @school.dn,
      :givenName => "Severus",
      :sn => "Snape",
      :uid => "severus.snape",
      :role_name => "Staff",
      :new_password => config.default_password,
      :new_password_confirmation => config.default_password,
      :puavoEduPersonAffiliation => "teacher"
    )
    config.dn = teacher.dn
  end

  env.define :admin do |config|
    admin = User.create!(
      :puavoSchool => @school.dn,
      :givenName => "Minerva",
      :sn => "McGonagall",
      :uid => "minerva.mcgonagall",
      :role_name => "Staff",
      :new_password => config.default_password,
      :new_password_confirmation => config.default_password,
      :puavoEduPersonAffiliation => "admin",
      :school_admin => true
    )
    @school.add_admin(admin)
    config.dn = admin.dn
  end

  env.define :new_admin do |config|
    admin = User.create!(
      :puavoSchool => @school.dn,
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

  env.define :owner do |config|
    config.dn = User.find(:first, :attribute => "uid", :value => "cucumber").dn.to_s
    config.password = "cucumber"
  end

  env.define :student1 do |config|
    student1 = User.create!(
      :puavoSchool => @school.dn,
      :givenName => "Harry",
      :sn => "Potter",
      :mail => "harry@example.com",
      :uid => "harry.potter",
      :role_name => "Class 4",
      :new_password => config.default_password,
      :new_password_confirmation => config.default_password,
      :puavoEduPersonAffiliation => "student"
    )
    config.dn = student1.dn
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
        env.admin.can_modify :school, [ :replace, :puavoSchoolAdmin, [env.student1.dn] ]
      }.should raise_error InsufficientAccessRights

    end

    it "should allow owner to write school attributes" do
      env.owner.can_modify :school, [ :replace, :displayName, ["Test school"] ]
    end

    it "should allow owner to write school puavoSchoolAdmin attribute" do
      env.owner.can_modify :school, [ :replace, :puavoSchoolAdmin, [env.new_admin.dn] ]
    end

  end
  
end
