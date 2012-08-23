
require 'spec_helper'
require 'acl_helper'


describe "ACL" do

  env = LDAPTestEnv.new

  before(:all) { env.reset }

  describe "groups" do
    it "should enforce basic group permissions" do
      env.owner.can_read :group, [:displayName, :puavoSchool]
      env.admin.can_read :group, [:displayName, :puavoSchool]
      env.teacher.can_read :group, [:displayName, :puavoSchool]
      env.student.can_read :group, [:displayName, :puavoSchool]

      env.student.cannot_modify :group, [ :replace, :displayName, ["newname"] ], InsufficientAccessRights
      env.teacher.cannot_modify :group, [ :replace, :displayName, ["newname"] ], InsufficientAccessRights
    end



  end

end
