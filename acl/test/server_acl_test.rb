env = LDAPTestEnv.new

env.validate "server" do
  owner.can_modify bootserver, [ :replace, :puavoHostname, [ "boot02" ] ]
  owner.can_modify bootserver, [ :replace, :description,   [ "test"   ] ]

  admin.can_search bootserver
  admin.can_read   bootserver, [ :dn, :puavoHostname ]

  admin.cannot_read bootserver,  [ :description   ], InsufficientAccessRights
  admin.cannot_read bootserver2, [ :puavoHostname ], InsufficientAccessRights

  admin.cannot_modify bootserver, [ :replace, :puavoHostname, [ "boot03" ] ],
                                  InsufficientAccessRights

  #
  # Bootserver should be able to read mostly everything, because of ldap
  # replication.  Just test some things.
  #

  user_attribute_list = [ :puavoEduPersonAffiliation,
                          :puavoId,
                          :puavoLocale,
                          :puavoSchool,
                          :sn ]
  bootserver.can_read student, user_attribute_list

  device_attribute_list = [ :macAddress,
                            :puavoDeviceType,
                            :puavoHostname,
                            :puavoSchool ]

  bootserver.can_read fatclient, device_attribute_list
  bootserver.can_read laptop,    device_attribute_list

  # Bootserver must be able to write device information for fatclients.
  bootserver.can_modify fatclient,
    [ :replace, :puavoDeviceHWInfo, [ '{ "some": "stuff" }' ] ]
end
