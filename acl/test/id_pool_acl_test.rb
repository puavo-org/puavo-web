
env = LDAPTestEnv.new

env.validate "id pool" do

  id_pool_attributes = [ :cn,
                         :puavoNextRid,
                         :puavoNextDatabaseId,
                         :puavoNextKadminPort,
                         :puavoNextGidNumber,
                         :puavoNextUidNumber,
                         :puavoNextId ]

    env.admin.cannot_read   :id_pool,   id_pool_attributes,                                   InsufficientAccessRights
    env.admin.cannot_modify :id_pool,   [:replace,              :puavoNextId,  ["12345"] ],   InsufficientAccessRights

    env.puavo.can_read   :id_pool, id_pool_attributes
    env.puavo.can_modify :id_pool, [:replace,           :puavoNextId,  ["12345"] ]
end
