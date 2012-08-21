require 'spec_helper'
require 'acl_helper'


describe "ACL" do


  env = LDAPTestEnv.new

  puts "Creating models"

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


  env.define :teacher2 do |config|
    teacher2 = User.create!(
      :puavoSchool => @school.dn,
      :givenName => "Gilderoy",
      :sn => "Lockhart",
      :uid => "gilderoy.lockhart",
      :role_name => "Staff",
      :new_password => config.default_password,
      :new_password_confirmation => config.default_password,
      :puavoEduPersonAffiliation => "teacher"
    )
    config.dn = teacher2.dn
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

  env.define :student2 do |config|
    student2 = User.create!(
      :puavoSchool => @school.dn,
      :givenName => "Ron",
      :mail => "ron@example.com",
      :sn => "Wesley",
      :uid => "ron.wesley",
      :role_name => "Class 4",
      :new_password => config.default_password,
      :new_password_confirmation => config.default_password,
      :puavoEduPersonAffiliation => "student"
    )
    config.dn = student2.dn
  end

  env.define :other_school do |config|
    @other_school = School.create!(
      :cn => "slytherin",
      :displayName => "Slytherin"
    )
    config.dn = @other_school.dn

    Role.create!(
      :displayName => "Class 4",
      :puavoSchool => @other_school.dn
    )
  end


  env.define :other_school_student do |config|
    other_school_student = User.create!(
      :puavoSchool => @other_school.dn,
      :givenName => "Draco",
      :sn => "Malfoy",
      :mail => "malfoy@example.com",
      :uid => "draco.malfoy",
      :role_name => "Class 4",
      :new_password => config.default_password,
      :new_password_confirmation => config.default_password,
      :puavoEduPersonAffiliation => "student"
    )
    config.dn = other_school_student
  end



  describe "password" do

    before(:each) do
      env.reset
    end

    it "should allow students to change their own passwords" do
      env.student1.can_set_password_for :student1
    end

    it "should not allow students to change other's passwords" do
      lambda {
        env.student1.can_set_password_for :student2
      }.should raise_error(LDAPException)
    end

    it "should allow school admin to change student password" do
      env.admin.can_set_password_for :student1
    end

    it "should allow teacher to change student password" do
      env.teacher.can_set_password_for :student1
    end

    it "should not allow teachers to change other teacher's paswords" do
      lambda {
        env.teacher.can_set_password_for :teacher2
      }.should raise_error(LDAPException)
    end


    # it "should allow school admins to change students of other schools" do
    #   env.admin.can_set_password_for :other_school_student
    # end

  end



  describe "user attributes" do

    before :all do
      env.reset
    end

    it "should allow students to read their own attributes" do
      env.student1.can_read :student1, [:sn, :givenName]
    end

    it "should allow students to read other students" do
      env.student1.can_read :student2, [:sn, :givenName, :uid]
    end

    it "should not allow teachers to modify students" do
      lambda {
        env.teacher.can_modify :student1, [:replace, :givenName, ["newname"]]
      }.should raise_error(InsufficientAccessRights)
    end

    it "should allow student to modify its own email" do
      env.student1.can_modify :student1, [:replace, :mail, ["foo@example.com"]]
    end

    it "should not allow student to modify its own name" do
      lambda {
        env.student1.can_modify :student1, [:replace, :givenName, ["bad"]]
      }.should raise_error(InsufficientAccessRights)
    end

    it "should not allow users to have same email addresses" do

      env.student1.can_modify :student1, [:replace, :mail, ["foo@example.com"]]

      lambda {
          env.student1.can_modify :student2, [:replace, :mail, ["foo@example.com"]]
      }.should raise_error(ConstraintViolation)

    end

    it "should not allow students to modify other students" do
        lambda {
          env.student1.can_modify :student2, [:replace, :givenName, ["newname"]]
        }.should raise_error(InsufficientAccessRights)

        lambda {
          env.student1.can_modify :student2, [:replace, :mail, ["bad@example.com"]]
        }.should raise_error(InsufficientAccessRights)
    end

    it "should allow admins to modify students" do
        env.admin.can_modify :student1, [:replace, :givenName, ["newname"]]
    end

    it "should not allow teachers to change admin attributes" do
      lambda {
        env.teacher.can_modify :admin, [:replace, :givenName, ["newname"]]
      }.should raise_error(InsufficientAccessRights)
    end

  end


  # it "should not allow teachers to change admin passwords" do
  # end



  # it "should allow only organisation owner to change organisation attributes" do
  # end


end
