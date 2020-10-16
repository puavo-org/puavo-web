env = LDAPTestEnv.new

env.validate "Slave Servers" do
  # slave servers can read everything but not modify anything

  slave.cannot_modify bootserver,
                      [ :replace, :puavoHostname, [ 'newboot01' ] ],
                      InsufficientAccessRights
  slave.cannot_modify student,
                      [ :replace, :mail, [ 'foobar@example.com' ] ],
                      InsufficientAccessRights
  slave.cannot_set_password_for admin, LDAPTestEnvException

  slave.can_read bootserver, [ :puavoHostname   ]
  slave.can_read student,    [ :mail            ]
  slave.can_read teacher,    [ :userPassword    ]
  slave.can_read owner,      [ :sambaNTPassword ]
end
