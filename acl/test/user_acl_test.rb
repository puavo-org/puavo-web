

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
  teacher.cannot_set_password_for teacher2,  LDAPTestEnvException
  reset
  admin.can_set_password_for other_school_student
  reset
  ticket.cannot_set_password_for student, LDAPTestEnvException
  reset
  ticket.cannot_set_password_for teacher, LDAPTestEnvException
  reset
  ticket.cannot_set_password_for admin, LDAPTestEnvException
end



env.validate "user attributes"  do

  student.can_read student,        [:sn,       :givenName,  :uid]
  student.can_read student2,       [:sn,       :givenName,  :uid]
  student.can_read teacher,        [:sn,       :givenName,  :uid]
  student.can_read admin,          [:sn,       :givenName,  :uid]

  student.cannot_modify student,   [:replace,  :givenName,  ["bad"]],              InsufficientAccessRights
  student.cannot_modify student2,  [:replace,  :givenName,  ["newname"]],          InsufficientAccessRights
  student.cannot_modify student2,  [:replace,  :mail,       ["bad@example.com"]],  InsufficientAccessRights

  teacher.cannot_modify student,   [:replace,  :givenName,  ["newname"]],          InsufficientAccessRights

  admin.can_modify student,        [:replace,  :givenName,  ["newname"]]
  admin.can_modify teacher,        [:replace,  :givenName,  ["newname"]]

  teacher.cannot_modify admin,     [:replace,  :givenName,  ["newname"]],          InsufficientAccessRights

  ticket.can_read student, [ :objectClass,
                             :uid,
                             :mail,
                             :puavoId,
                             :eduPersonPrincipalName,
                             :puavoEduPersonAffiliation,
                             :uidNumber,
                             :gidNumber,
                             :homeDirectory,
                             :givenName,
                             :sn,
                             :puavoPreferredDesktop,
                             :loginShell,
                             :displayName,
                             :puavoEduPersonReverseDisplayName,
                             :puavoEduPersonPersonnelNumber,
                             :jpegPhoto,
                             :preferredLanguage,
                             :puavoLocale,
                             :telephoneNumber,
                             :puavoAcceptedTerms
                           ]

  puavo.can_read student, [ :eduPersonPrincipalName,
                            :gidNumber,
                            :givenName,
                            :homeDirectory,
                            :loginShell,
                            :objectClass,
                            :puavoAcceptedTerms,
                            :puavoEduPersonAffiliation,
                            :puavoId,
                            :puavoPreferredDesktop,
                            :sn,
                            :uid,
                            :uidNumber ]
end

env.validate "should not allow same email for two students" do
  student.can_modify student,       [:replace,  :mail,  ["foo@example.com"]]
  student2.cannot_modify student2,  [:replace,  :mail,  ["foo@example.com"]],  ConstraintViolation
end

