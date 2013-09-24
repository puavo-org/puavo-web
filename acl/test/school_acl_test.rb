
env = LDAPTestEnv.new

env.define :new_admin do |config|
  admin = User.create(
    :puavoSchool => env.school.dn,
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

school_attributes = [
  :cn,
  :displayName,
  :gidNumber,
  :member,
  :memberUid,
  :objectClass,
  :puavoId,
  :puavoSchoolAdmin,
  :sambaGroupType,
  :sambaSID,
]

env.validate "school" do
  admin.can_read school, school_attributes
  student.can_read school, school_attributes
  teacher.can_read school, school_attributes

  owner.can_modify school, [ :replace, :displayName,        ["Test school"]   ]
  owner.can_modify school, [ :add,     :puavoSchoolAdmin,   [new_admin.dn]    ]
  owner.can_modify school, [ :replace, :puavoPrinterQueue,  [printer.dn]      ]

  student.cannot_modify school, [ :replace, :displayName,        ["newname"]   ], InsufficientAccessRights
  student.cannot_modify school, [ :replace, :puavoPrinterQueue,  [printer.dn]  ], InsufficientAccessRights

  admin.cannot_modify school, [ :replace, :puavoSchoolAdmin,   [student.dn]   ], InsufficientAccessRights
  admin.can_modify    school, [ :replace, :puavoPrinterQueue,  [printer.dn]   ]
end


