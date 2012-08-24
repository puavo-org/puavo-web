
env = LDAPTestEnv.new

env.validate "Samba Domain" do
  admin.can_read       domain_users,   [:memberUid]
  admin.can_modify     domain_users,   [:replace,    :memberUid,  ["testexampleuid"]]
  admin.cannot_read    domain_admins,  [:memberUid],                                    InsufficientAccessRights
  admin.cannot_modify  domain_admins,  [:replace,    :memberUid,  ["testexampleuid"]],  InsufficientAccessRights
  owner.can_read       domain_admins,  [:memberUid]
  owner.can_modify     domain_admins,  [:replace,    :memberUid,  ["testexampleuid"]]
end
