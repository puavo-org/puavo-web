
require 'spec_helper'
require 'acl_helper'


describe "ACL" do

  env = LDAPTestEnv.new


    describe "groups" do
      it "should enforce basic group permissions" do
        env.with_data do

          owner.can_read group, [:displayName, :puavoSchool]
          admin.can_read group, [:displayName, :puavoSchool]
          teacher.can_read group, [:displayName, :puavoSchool]
          student.can_read group, [:displayName, :puavoSchool]

          student.cannot_modify group, [ :replace, :displayName, ["newname"] ], InsufficientAccessRights
          teacher.cannot_modify group, [ :replace, :displayName, ["newname"] ], InsufficientAccessRights

        end
      end
  end
end
