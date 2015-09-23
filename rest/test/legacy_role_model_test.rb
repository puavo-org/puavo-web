require_relative "./helper"
require_relative "../lib/ldapmodel"


describe PuavoRest::LegacyRole do

  before(:each) do
    Puavo::Test.clean_up_ldap
    @school = School.create(
      :cn => "gryffindor",
      :displayName => "Gryffindor",
      :puavoSchoolHomePageURL => "schoolhomepage.example"
    )

    @group = Group.new
    @group.cn = "group1"
    @group.displayName = "Group 1"
    @group.puavoSchool = @school.dn
    @group.save!

    @role_al = Role.new
    @role_al.displayName = "Some role"
    @role_al.puavoSchool = @school.dn
    @role_al.groups << @group
    @role_al.save!

    LdapModel.setup(
      :organisation => PuavoRest::Organisation.default_organisation_domain!,
      :rest_root => "http://" + CONFIG["default_organisation_domain"],
      :credentials => {
        :dn => PUAVO_ETC.ldap_dn,
        :password => PUAVO_ETC.ldap_password }
    )

    @user = PuavoRest::User.new(
      :object_classes => ["top", "posixAccount", "inetOrgPerson", "puavoEduPerson", "sambaSamAccount", "eduPerson"],
      :first_name => "Heli",
      :last_name => "Kopteri",
      :username => "heli",
      :roles => ["staff"],
      :email => "heli.kopteri@example.com",
      :school_dns => [@school.dn.to_s],
      :password => "userpwlonger"
    )
    @user.save!

    @user2 = PuavoRest::User.new(
      :object_classes => ["top", "posixAccount", "inetOrgPerson", "puavoEduPerson", "sambaSamAccount", "eduPerson"],
      :first_name => "Foo",
      :last_name => "Bar",
      :username => "foo",
      :roles => ["staff"],
      :email => "foo.bar@example.com",
      :school_dns => [@school.dn.to_s],
      :password => "userpwlonger"
    )
    @user2.save!

    @role = PuavoRest::LegacyRole.by_dn(@role_al.dn)
    @role.add_member(@user)
    @role.add_member(@user2)
    @role.save!
  end

  it "can have members" do
    role = PuavoRest::LegacyRole.by_dn(@role_al.dn)
    assert role.member_usernames.include?("heli"), "has heli"
    assert role.member_usernames.include?("foo"), "has foo"
  end

  it "gives it's groups to the user" do
    group = Group.find(@group.dn)
    assert_equal Array, group.memberUid.class
    assert(
      group.memberUid.include?(@user.username),
      "has the group from the role"
    )
  end

  it "can remove member" do
    role = PuavoRest::LegacyRole.by_dn(@role_al.dn)
    role.remove_member(@user)

    assert !role.member_usernames.include?("heli"), "heli has been removed 1"
    assert role.member_usernames.include?("foo"), "foo is still present 1"
    role.save!

    # Refresh the model and ensure that it's actually removed
    role = PuavoRest::LegacyRole.by_dn(@role_al.dn)
    assert !role.member_usernames.include?("heli"), "heli has been removed 2"
    assert role.member_usernames.include?("foo"), "foo is still present 2"

    # Group has been remove too
    group = Group.find(@group.dn)
    assert(
      !Array(group.memberUid).include?(@user.username),
      "the group has been removed within the role"
    )
  end

end
