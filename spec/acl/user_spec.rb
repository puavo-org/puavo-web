require 'spec_helper'
require 'acl_helper'


describe "ACL" do

  env = LDAPTestEnv.new


  describe "password" do

    before(:each) { env.reset }

    it "should allow students to change their own passwords" do
      env.student.can_set_password_for :student
    end

    it "should not allow students to change other's passwords" do
      lambda {
        env.student.can_set_password_for :student2
      }.should raise_error LDAPException
    end

    it "should allow school admin to change student password" do
      env.admin.can_set_password_for :student
    end

    it "should allow school admin to change teacher's passwords" do
      env.admin.can_set_password_for :teacher
    end

    it "should allow teacher to change student password" do
      env.teacher.can_set_password_for :student
    end

    it "should not allow teachers to change other teacher's paswords" do
      lambda {
        env.teacher.can_set_password_for :teacher2
      }.should raise_error LDAPException
    end

    it "should allow school admins to change attributes of students in other schools" do
      env.admin.can_set_password_for :other_school_student
    end

  end


  describe "user attributes" do

    before(:all) { env.reset }

    it "should allow students to read their own attributes" do
      env.student.can_read :student, [:sn, :givenName]
    end

    it "should allow students to read other users" do
      [:teacher, :student2, :admin].each do |user|
        env.student.can_read user, [:sn, :givenName, :uid]
      end
    end

    it "should not allow teachers to modify students" do
      lambda {
        env.teacher.can_modify :student, [:replace, :givenName, ["newname"]]
      }.should raise_error InsufficientAccessRights
    end

    it "should allow student to modify its own email" do
      env.student.can_modify :student, [:replace, :mail, ["foo@example.com"]]
    end

    it "should not allow student to modify its own name" do
      lambda {
        env.student.can_modify :student, [:replace, :givenName, ["bad"]]
      }.should raise_error InsufficientAccessRights
    end

    it "should not allow users to have same email addresses" do

      env.student.can_modify :student, [:replace, :mail, ["foo@example.com"]]

      lambda {
          env.student.can_modify :student2, [:replace, :mail, ["foo@example.com"]]
      }.should raise_error ConstraintViolation

    end

    it "should not allow students to modify other students" do
        lambda {
          env.student.can_modify :student2, [:replace, :givenName, ["newname"]]
        }.should raise_error InsufficientAccessRights

        lambda {
          env.student.can_modify :student2, [:replace, :mail, ["bad@example.com"]]
        }.should raise_error InsufficientAccessRights
    end

    it "should allow admins to modify students" do
        env.admin.can_modify :student, [:replace, :givenName, ["newname"]]
    end

    it "should allow admins to modify teachers" do
        env.admin.can_modify :teacher, [:replace, :givenName, ["newname"]]
    end

    it "should not allow teachers to change admin attributes" do
      lambda {
        env.teacher.can_modify :admin, [:replace, :givenName, ["newname"]]
      }.should raise_error InsufficientAccessRights
    end

  end


  # it "should not allow teachers to change admin passwords" do
  # end



  # it "should allow only organisation owner to change organisation attributes" do
  # end


end
