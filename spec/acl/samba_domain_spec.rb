require 'spec_helper'
require 'acl_helper'


describe "ACL" do

  env = LDAPTestEnv.new

  describe "Samba Domain" do
    before(:all) { env.reset }

    it "should enforce basic Samba Domain permissions" do
      env.student
      env.admin.can_read       :domain_users,   [:memberUid]
      env.admin.can_modify     :domain_users,   [:replace,    :memberUid,  ["testexampleuid"]]
      env.admin.cannot_read    :domain_admins,  [:memberUid],                                    InsufficientAccessRights
      env.admin.cannot_modify  :domain_admins,  [:replace,    :memberUid,  ["testexampleuid"]],  InsufficientAccessRights
      env.owner.can_read       :domain_admins,  [:memberUid]
      env.owner.can_modify     :domain_admins,  [:replace,    :memberUid,  ["testexampleuid"]]
    end
  end

end
