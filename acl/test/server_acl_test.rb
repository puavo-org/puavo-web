env = LDAPTestEnv.new


env.validate "server" do
  owner.can_modify bootserver, [ :replace, :puavoHostname,                ["boot02"]   ]
  owner.can_modify bootserver, [ :replace, :description,                  ["test"]   ]

  admin.can_read bootserver, [ :dn, :puavoHostname ]

  admin.cannot_read bootserver, [ :description ], InsufficientAccessRights

  admin.cannot_modify bootserver, [ :replace, :puavoHostname,                ["boot03"]   ], InsufficientAccessRights

end
