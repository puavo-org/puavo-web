env = LDAPTestEnv.new

env.validate "host" do
  laptop.can_modify laptop, [ :replace, :puavoDevicePrimaryUser, [ owner.dn ] ]

  # Laptops must be able to read uid numbers from all users, so it can know
  # the list of users in an organisation and that data from removed users is
  # deleted correctly.

  laptop.can_read admin, [ :dn, :uid, :uidNumber, :givenName, :sn ]
  laptop.can_read other_school_admin, [ :dn, :uid, :uidNumber, :givenName, :sn ]

  laptop.can_read student, [ :dn, :uid, :uidNumber ]
  laptop.can_read teacher, [ :dn, :uid, :uidNumber  ]
  laptop.can_read other_school_student, [ :dn, :uid, :uidNumber  ]
  laptop.can_read other_school_teacher, [ :dn, :uid, :uidNumber  ]

  laptop.cannot_read student, [ :givenName, :sn ], InsufficientAccessRights
  laptop.cannot_read teacher, [ :givenName, :sn ], InsufficientAccessRights
  laptop.cannot_read other_school_student, [ :givenName, :sn ],
                                           InsufficientAccessRights
  laptop.cannot_read other_school_teacher, [ :givenName, :sn ],
                                           InsufficientAccessRights

  admin.can_read              fatclient, [ :dn, :puavoHostname ]
  other_school_admin.can_read fatclient, [ :dn, :puavoHostname ]

  admin.can_read              laptop, [ :dn, :puavoHostname ]
  other_school_admin.can_read laptop, [ :dn, :puavoHostname ]
end
