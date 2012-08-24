
env = LDAPTestEnv.new

env.validate "should validate basic role permissions" do
  env.admin.can_read :role, [:displayName, :puavoSchool ]
  env.teacher.cannot_read :role, [:displayName, :puavoSchool ], InsufficientAccessRights
  env.student.cannot_read :role, [:displayName, :puavoSchool ], InsufficientAccessRights
  env.admin.can_modify :role, [ :replace, :displayName, ["newname"] ]
  env.teacher.cannot_modify :role, [ :replace, :displayName, ["badnaname"] ], InsufficientAccessRights
  env.student.cannot_modify :role, [ :replace, :displayName, ["badnaname2"] ], InsufficientAccessRights
end
