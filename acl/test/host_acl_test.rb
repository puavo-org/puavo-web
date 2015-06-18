

env = LDAPTestEnv.new

env.validate "laptop" do
  laptop.can_modify laptop, [ :replace, :puavoDevicePrimaryUser,                [owner.dn]   ]
end

