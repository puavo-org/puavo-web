
env = LDAPTestEnv.new

env.validate "Role" do
  admin.can_read role, [:displayName, :puavoSchool ]
  teacher.cannot_read role, [:displayName, :puavoSchool ], InsufficientAccessRights
  student.cannot_read role, [:displayName, :puavoSchool ], InsufficientAccessRights
  admin.can_modify role, [ :replace, :displayName, ["newname"] ]
  teacher.cannot_modify role, [ :replace, :displayName, ["badnaname"] ], InsufficientAccessRights
  student.cannot_modify role, [ :replace, :displayName, ["badnaname2"] ], InsufficientAccessRights
end
