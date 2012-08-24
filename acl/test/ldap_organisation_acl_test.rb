
env = LDAPTestEnv.new

env.validate "organisation" do

  # Owner cannot modify following attributes
  env.owner.cannot_modify :organisation, [ :replace, :puavoKerberosRealm,            ["EXAMPLE2.OPINSYS.NET"]        ],  InsufficientAccessRights
  env.owner.cannot_modify :organisation, [ :replace, :sambaDomainName,               ["EDUEXAMPLE2"]                 ],  InsufficientAccessRights
  env.owner.cannot_modify :organisation, [ :replace, :puavoPuppetHost,               ["example2.puppet.opinsys.net"] ],  InsufficientAccessRights
  env.owner.cannot_modify :organisation, [ :replace, :puavoDomain,                   ["example2.opinsys.net"]        ],  InsufficientAccessRights
  env.owner.cannot_modify :organisation, [ :replace, :puavoKadminPort,               ["99999"]                       ],  InsufficientAccessRights
  env.owner.cannot_modify :organisation, [ :replace, :puavoRemoteDesktopPrivateKey,  ["dfsadfowieroasdfasodf"]       ],  InsufficientAccessRights
  env.owner.cannot_modify :organisation, [ :add,     :owner,                         [env.teacher.dn]                ],  InsufficientAccessRights



  # Owner can modify following attributes
  env.owner.can_modify :organisation, [ :replace, :description,                  ["Example description of example2 organisation"] ]
  env.owner.can_modify :organisation, [ :replace, :eduOrgHomePageURI,            ["http://www.example.com"]                       ]
  env.owner.can_modify :organisation, [ :replace, :facsimileTelephoneNumber,     ["+358017123456789"]                             ]
  env.owner.can_modify :organisation, [ :replace, :l,                            ["Example city"]                                 ]
  env.owner.can_modify :organisation, [ :replace, :o,                            ["Example2"]                                     ]
  env.owner.can_modify :organisation, [ :replace, :postOfficeBox,                ["PL 12345"]                                     ]
  env.owner.can_modify :organisation, [ :replace, :postalAddress,                ["Examplestreet 55"]                             ]
  env.owner.can_modify :organisation, [ :replace, :postalCode,                   ["1234567"]                                      ]
  env.owner.can_modify :organisation, [ :replace, :preferredLanguage,            ["English"]                                      ]
  env.owner.can_modify :organisation, [ :replace, :puavoDeviceAutoPowerOffMode,  ["custom"]                                       ]
  env.owner.can_modify :organisation, [ :replace, :puavoDeviceOffHour,           ["17"]                                           ]
  env.owner.can_modify :organisation, [ :replace, :puavoDeviceOnHour,            ["07"]                                           ]
  env.owner.can_modify :organisation, [ :replace, :puavoEduOrgAbbreviation,      ["example2"]                                     ]
  env.owner.can_modify :organisation, [ :replace, :st,                           ["Example state"]                                ]
  env.owner.can_modify :organisation, [ :replace, :street,                       ["Examplestreet 55"]                             ]
  env.owner.can_modify :organisation, [ :replace, :telephoneNumber,              ["+358017123456789"]                             ]
  env.owner.can_modify :organisation, [ :replace, :eduOrgLegalName,              ["example2"]                                     ]

  # Owner can read following attributes
  env.owner.can_read :organisation, [ :cn,
                                      :description,
                                      :eduOrgHomePageURI,
                                      :eduOrgLegalName,
                                      :facsimileTelephoneNumber,
                                      :l,
                                      :o,
                                      :owner,
                                      :postOfficeBox,
                                      :postalAddress,
                                      :postalCode,
                                      :preferredLanguage,
                                      :puavoDeviceAutoPowerOffMode,
                                      :puavoDeviceOffHour,
                                      :puavoDeviceOnHour,
                                      :puavoDomain,
                                      :puavoEduOrgAbbreviation,
                                      :puavoKadminPort,
                                      :puavoKerberosRealm,
                                      :puavoPuppetHost,
                                      :puavoRemoteDesktopPrivateKey,
                                      :sambaDomainName,
                                      :st,
                                      :street,
                                      :telephoneNumber ]

end
