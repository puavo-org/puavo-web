
require 'spec_helper'
require 'acl_helper'


describe "ACL" do

  env = LDAPTestEnv.new

  describe "role" do

    before(:all) { env.reset }

    it "should allow admins to read roles" do
      env.admin.can_read :role, [:displayName, :puavoSchool ]
    end

    it "should allow admins to edit roles" do
      env.admin.can_modify :role, [ :replace, :displayName, ["newname"] ]
    end

    it "should not allow teachers to edit roles" do
      lambda {
        env.teacher.can_modify :role, [ :replace, :displayName, ["badnaname"] ]
      }.should raise_error InsufficientAccessRights
    end

    it "should not allow students to edit roles" do
      lambda {
        env.student.can_modify :role, [ :replace, :displayName, ["badnaname2"] ]
      }.should raise_error InsufficientAccessRights
    end


  end
end
