
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

  owner.can_modify school, [ :replace, :displayName,                ["Test school"]   ]
  owner.can_modify school, [ :add,     :puavoSchoolAdmin,           [new_admin.dn]    ]
  owner.can_modify school, [ :replace, :puavoPrinterQueue,          [printer.dn]      ]
  owner.can_modify school, [ :replace, :puavoWirelessPrinterQueue,  [printer.dn]      ]

  student.cannot_modify school, [ :replace, :puavoSchoolAdmin,           [student.dn]            ], InsufficientAccessRights
  student.cannot_modify school, [ :replace, :puavoBillingInfo,           ["test"]                ], InsufficientAccessRights
  student.cannot_modify school, [ :replace, :displayName,                ["newname"]             ], InsufficientAccessRights
  student.cannot_modify school, [ :replace, :puavoPrinterQueue,          [printer.dn]            ], InsufficientAccessRights
  student.cannot_modify school, [ :replace, :puavoWirelessPrinterQueue,  [printer.dn]            ], InsufficientAccessRights
  student.cannot_modify school, [ :replace, :displayName,                ["Test name"]           ], InsufficientAccessRights
  student.cannot_modify school, [ :replace, :puavoNamePrefix,            ["test prefix"]         ], InsufficientAccessRights
  student.cannot_modify school, [ :replace, :puavoSchoolHomePageURL,     ["http://www.test.com"] ], InsufficientAccessRights
  student.cannot_modify school, [ :replace, :description,                ["test"]                ], InsufficientAccessRights
  student.cannot_modify school, [ :replace, :cn,                         ["testname"]            ], InsufficientAccessRights
  student.cannot_modify school, [ :replace, :telephoneNumber,            ["0123456789"]          ], InsufficientAccessRights
  student.cannot_modify school, [ :replace, :facsimileTelephoneNumber,   ["0123456789"]          ], InsufficientAccessRights
  student.cannot_modify school, [ :replace, :l,                          ["test"]                ], InsufficientAccessRights
  student.cannot_modify school, [ :replace, :street,                     ["test"]                ], InsufficientAccessRights
  student.cannot_modify school, [ :replace, :postOfficeBox,              ["test"]                ], InsufficientAccessRights
  student.cannot_modify school, [ :replace, :postalAddress,              ["test"]                ], InsufficientAccessRights
  student.cannot_modify school, [ :replace, :postalCode,                 ["test"]                ], InsufficientAccessRights
  student.cannot_modify school, [ :replace, :st,                         ["test"]                ], InsufficientAccessRights
  student.cannot_modify school, [ :replace, :preferredLanguage,          ["en"]                  ], InsufficientAccessRights
  student.cannot_modify school, [ :replace, :jpegPhoto,                  ["test"]                ], InsufficientAccessRights
  student.cannot_modify school, [ :replace, :puavoDeviceImage,           ["test-image"]          ], InsufficientAccessRights
  student.cannot_modify school, [ :replace, :puavoAllowGuest,            [false]                 ], InsufficientAccessRights
  student.cannot_modify school, [ :replace, :puavoPersonalDevice,        [false]                 ], InsufficientAccessRights


  admin.cannot_modify school, [ :replace, :puavoSchoolAdmin,           [student.dn]            ], InsufficientAccessRights
  admin.cannot_modify school, [ :replace, :puavoBillingInfo,           ["test"]                ], InsufficientAccessRights
  admin.can_modify    school, [ :replace, :puavoPrinterQueue,          [printer.dn]            ]
  admin.can_modify    school, [ :replace, :puavoWirelessPrinterQueue,  [printer.dn]            ]
  admin.can_modify    school, [ :replace, :displayName,                ["Test name"]           ]
  admin.can_modify    school, [ :replace, :puavoNamePrefix,            ["test prefix"]         ]
  admin.can_modify    school, [ :replace, :puavoSchoolHomePageURL,     ["http://www.test.com"] ]
  admin.can_modify    school, [ :replace, :description,                ["test"]                ]
  admin.can_modify    school, [ :replace, :cn,                         ["testname"]            ]
  admin.can_modify    school, [ :replace, :telephoneNumber,            ["0123456789"]          ]
  admin.can_modify    school, [ :replace, :facsimileTelephoneNumber,   ["0123456789"]          ]
  admin.can_modify    school, [ :replace, :l,                          ["test"]                ]
  admin.can_modify    school, [ :replace, :street,                     ["test"]                ]
  admin.can_modify    school, [ :replace, :postOfficeBox,              ["test"]                ]
  admin.can_modify    school, [ :replace, :postalAddress,              ["test"]                ]
  admin.can_modify    school, [ :replace, :postalCode,                 ["test"]                ]
  admin.can_modify    school, [ :replace, :st,                         ["test"]                ]
  admin.can_modify    school, [ :replace, :preferredLanguage,          ["en"]                  ]
  admin.can_modify    school, [ :replace, :jpegPhoto,                  ["test"]                ]
  admin.can_modify    school, [ :replace, :puavoDeviceImage,           ["test-image"]          ]
  admin.can_modify    school, [ :replace, :puavoAllowGuest,            [false]                 ]
  admin.can_modify    school, [ :replace, :puavoPersonalDevice,        [false]                 ]

end


