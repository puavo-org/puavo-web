require 'spec_helper'
require 'acl_helper'


describe "ACL" do

  env = LDAPTestEnv.new


  describe "password" do
      before(:all) { env.reset }

      it "should enforce basic password change permissions" do

        env.student.can_set_password_for :student
        env.reset
        env.student.cannot_set_password_for :student2, LDAPTestEnvException
        env.reset
        env.admin.can_set_password_for :student
        env.reset
        env.admin.can_set_password_for :teacher
        env.reset
        env.teacher.can_set_password_for :student
        env.reset
        env.teacher.cannot_set_password_for :teacher2,  LDAPTestEnvException
        env.reset
        env.admin.can_set_password_for :other_school_student

      end

  end


  describe "user attributes" do

    before(:all) { env.reset }

    it "should enforce basic permissions" do

      env.student.can_read :student,        [:sn,       :givenName,  :uid]
      env.student.can_read :student2,       [:sn,       :givenName,  :uid]
      env.student.can_read :teacher,        [:sn,       :givenName,  :uid]
      env.student.can_read :admin,          [:sn,       :givenName,  :uid]

      env.student.cannot_modify :student,   [:replace,  :givenName,  ["bad"]],              InsufficientAccessRights
      env.student.cannot_modify :student2,  [:replace,  :givenName,  ["newname"]],          InsufficientAccessRights
      env.student.cannot_modify :student2,  [:replace,  :mail,       ["bad@example.com"]],  InsufficientAccessRights

      env.teacher.cannot_modify :student,   [:replace,  :givenName,  ["newname"]],          InsufficientAccessRights

      env.admin.can_modify :student,        [:replace,  :givenName,  ["newname"]]
      env.admin.can_modify :teacher,        [:replace,  :givenName,  ["newname"]]

      env.teacher.cannot_modify :admin,     [:replace,  :givenName,  ["newname"]],          InsufficientAccessRights

    end

    it "should not allow same email for two students" do
      env.student.can_modify :student,       [:replace,  :mail,  ["foo@example.com"]]
      env.student2.cannot_modify :student2,  [:replace,  :mail,  ["foo@example.com"]],  ConstraintViolation
    end


  end

end
