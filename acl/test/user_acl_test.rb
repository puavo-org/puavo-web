

env = LDAPTestEnv.new

env.validate "User passoword" do

  student.can_set_password_for student
  reset
  student.cannot_set_password_for student2, LDAPTestEnvException
  reset
  admin.can_set_password_for student
  reset
  admin.can_set_password_for teacher
  reset
  teacher.can_set_password_for student
  reset
  teacher.cannot_set_password_for teacher2, LDAPTestEnvException
  reset
  admin.cannot_set_password_for other_school_student, LDAPTestEnvException
  reset
  pwmgmt.can_set_password_for student
  reset
  pwmgmt.can_set_password_for teacher
  reset
  pwmgmt.can_set_password_for admin
end


env.validate "user attributes"  do

  student.can_read student, [:sn, :givenName, :uid, :puavoLocked]

  student.cannot_read student2, [:sn, :givenName, :uid], InsufficientAccessRights
  student.cannot_read teacher,  [:sn, :givenName, :uid], InsufficientAccessRights
  student.cannot_read admin,    [:sn, :givenName, :uid], InsufficientAccessRights

  student.cannot_modify student,   [:replace,  :givenName,  ["bad"]],              InsufficientAccessRights
  student.cannot_modify student,   [:replace,  :puavoLocked,["FALSE"]],            InsufficientAccessRights
  student.cannot_modify student2,  [:replace,  :givenName,  ["newname"]],          InsufficientAccessRights
  student.cannot_modify student2,  [:replace,  :mail,       ["bad@example.com"]],  InsufficientAccessRights

  teacher.cannot_modify student,   [:replace,  :givenName,  ["newname"]],          InsufficientAccessRights

  admin.can_modify student,        [:replace,  :givenName,  ["newname"]]
  admin.can_modify teacher,        [:replace,  :givenName,  ["newname"]]

  teacher.cannot_modify admin,     [:replace,  :givenName,  ["newname"]],          InsufficientAccessRights

  attribute_list = [ :eduPersonPrincipalName,
                     :gidNumber,
                     :givenName,
                     :homeDirectory,
                     :jpegPhoto,
                     :loginShell,
                     :mail,
                     :objectClass,
                     :preferredLanguage,
                     :puavoAcceptedTerms,
                     :puavoEduPersonAffiliation,
                     :puavoId,
                     :puavoLocale,
                     :sn,
                     :telephoneNumber,
                     :uid,
                     :uidNumber ]
  puavo.can_read student,  attribute_list
  pwmgmt.can_read student, attribute_list

  sysgroup_getent.can_read student, [ :puavoSchool ]
end

env.validate "should not allow same email for two students" do
  student.can_modify student,       [:replace,  :mail,  ["foo@example.com"]]
  student2.cannot_modify student2,  [:replace,  :mail,  ["foo@example.com"]],  ConstraintViolation
end

