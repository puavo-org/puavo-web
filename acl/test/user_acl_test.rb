env = LDAPTestEnv.new

env.validate 'user attributes' do
  student.can_read student, [ :sn, :givenName, :uid, :puavoLocked ]

  # students should *not* be able to read information on other users
  student.cannot_read student2, [ :sn, :givenName, :uid ],
                                InsufficientAccessRights
  student.cannot_read teacher, [ :sn, :givenName, :uid ],
                               InsufficientAccessRights
  student.cannot_read admin, [ :sn, :givenName, :uid ],
                             InsufficientAccessRights

  student.cannot_modify student, [ :replace, :givenName, ["bad"] ],
                                 InsufficientAccessRights
  student.cannot_modify student, [ :replace, :puavoLocked, ["FALSE"] ],
                                 InsufficientAccessRights
  student.cannot_modify student2, [ :replace, :givenName, [ "newname"] ],
                                  InsufficientAccessRights
  student.cannot_modify student2, [ :replace, :mail, [ "bad@example.com" ] ],
                                  InsufficientAccessRights

  teacher.cannot_modify student, [ :replace,  :givenName,  ["newname"] ],
                                 InsufficientAccessRights

  admin.can_modify student, [ :replace,  :givenName,  [ "newname" ] ]
  admin.can_modify teacher, [ :replace,  :givenName,  [ "newname" ] ]

  teacher.cannot_modify admin, [ :replace,  :givenName,  ["newname"] ],
                               InsufficientAccessRights

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
  student.can_modify student, [ :replace, :mail, [ "foo@example.com" ] ]
  student2.cannot_modify student2, [ :replace, :mail, [ "foo@example.com" ] ],
                                   ConstraintViolation
end
