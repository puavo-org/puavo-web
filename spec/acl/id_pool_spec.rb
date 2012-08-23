require 'spec_helper'
require 'acl_helper'


describe "ACL" do

  env = LDAPTestEnv.new


  describe "id pool" do

    before(:all) { env.reset }

    id_pool_attributes = [ :cn,
                           :puavoNextRid,
                           :puavoNextDatabaseId,
                           :puavoNextKadminPort,
                           :puavoNextGidNumber,
                           :puavoNextUidNumber,
                           :puavoNextId ]

    it "should not allow admins to manage id pool" do
      env.admin.cannot_read   :id_pool,   id_pool_attributes,                                   InsufficientAccessRights
      env.admin.cannot_modify :id_pool,   [:replace,              :puavoNextId,  ["12345"] ],   InsufficientAccessRights
    end

    it "should allow puavo to manage id pool" do
      env.puavo.can_read   :id_pool, id_pool_attributes
      env.puavo.can_modify :id_pool, [:replace,           :puavoNextId,  ["12345"] ]
    end

  end
end
