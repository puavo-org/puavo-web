
env = LDAPTestEnv.new

env.validate "id pool" do

  id_pool_attributes = [ :cn,
                         :puavoNextRid,
                         :puavoNextDatabaseId,
                         :puavoNextKadminPort,
                         :puavoNextGidNumber,
                         :puavoNextUidNumber,
                         :puavoNextId ]

    admin.cannot_read   id_pool,   id_pool_attributes,                                   InsufficientAccessRights
    admin.cannot_modify id_pool,   [:replace,              :puavoNextId,  ["12345"] ],   InsufficientAccessRights

    puavo.can_read   id_pool, id_pool_attributes
    puavo.can_modify id_pool, [:replace,           :puavoNextId,  ["12345"] ]
end
