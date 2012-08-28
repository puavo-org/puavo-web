

env = LDAPTestEnv.new

env.validate "groups" do
  owner.can_read group, [:displayName, :puavoSchool]
  admin.can_read group, [:displayName, :puavoSchool]
  teacher.can_read group, [:displayName, :puavoSchool]
  student.can_read group, [:displayName, :puavoSchool]

  student.cannot_modify group, [ :replace, :displayName, ["newname"] ], InsufficientAccessRights
  teacher.cannot_modify group, [ :replace, :displayName, ["newname"] ], InsufficientAccessRights
end
