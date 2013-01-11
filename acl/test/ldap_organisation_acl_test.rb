
env = LDAPTestEnv.new

env.validate "Organisation" do

  # Owner cannot modify following attributes
  owner.cannot_modify organisation, [ :replace, :puavoKerberosRealm,            ["EXAMPLE2.OPINSYS.NET"]        ],  InsufficientAccessRights
  owner.cannot_modify organisation, [ :replace, :sambaDomainName,               ["EDUEXAMPLE2"]                 ],  InsufficientAccessRights
  owner.cannot_modify organisation, [ :replace, :puavoPuppetHost,               ["example2.puppet.opinsys.net"] ],  InsufficientAccessRights
  owner.cannot_modify organisation, [ :replace, :puavoDomain,                   ["example2.opinsys.net"]        ],  InsufficientAccessRights
  owner.cannot_modify organisation, [ :replace, :puavoKadminPort,               ["99999"]                       ],  InsufficientAccessRights
  owner.cannot_modify organisation, [ :replace, :puavoRemoteDesktopPrivateKey,  ["dfsadfowieroasdfasodf"]       ],  InsufficientAccessRights
  owner.cannot_modify organisation, [ :add,     :owner,                         [teacher.dn]                ],  InsufficientAccessRights



  # Owner can modify following attributes
  owner.can_modify organisation, [ :replace, :description,                  ["Example description of example2 organisation"] ]
  owner.can_modify organisation, [ :replace, :eduOrgHomePageURI,            ["http://www.example.com"]                       ]
  owner.can_modify organisation, [ :replace, :facsimileTelephoneNumber,     ["+358017123456789"]                             ]
  owner.can_modify organisation, [ :replace, :l,                            ["Example city"]                                 ]
  owner.can_modify organisation, [ :replace, :o,                            ["Example2"]                                     ]
  owner.can_modify organisation, [ :replace, :postOfficeBox,                ["PL 12345"]                                     ]
  owner.can_modify organisation, [ :replace, :postalAddress,                ["Examplestreet 55"]                             ]
  owner.can_modify organisation, [ :replace, :postalCode,                   ["1234567"]                                      ]
  owner.can_modify organisation, [ :replace, :preferredLanguage,            ["English"]                                      ]
  owner.can_modify organisation, [ :replace, :puavoDeviceAutoPowerOffMode,  ["custom"]                                       ]
  owner.can_modify organisation, [ :replace, :puavoDeviceOffHour,           ["17"]                                           ]
  owner.can_modify organisation, [ :replace, :puavoDeviceOnHour,            ["07"]                                           ]
  owner.can_modify organisation, [ :replace, :puavoEduOrgAbbreviation,      ["example2"]                                     ]
  owner.can_modify organisation, [ :replace, :st,                           ["Example state"]                                ]
  owner.can_modify organisation, [ :replace, :street,                       ["Examplestreet 55"]                             ]
  owner.can_modify organisation, [ :replace, :telephoneNumber,              ["+358017123456789"]                             ]
  owner.can_modify organisation, [ :replace, :eduOrgLegalName,              ["example2"]                                     ]

  # Owner can read following attributes
  owner.can_read organisation, [ :cn,
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
