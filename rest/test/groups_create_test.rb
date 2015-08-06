require_relative "./helper"
require_relative "../lib/ldapmodel"

describe LdapModel do

  before(:each) do
    Puavo::Test.clean_up_ldap

    LdapModel.setup(
      :organisation => PuavoRest::Organisation.default_organisation_domain!,
      :rest_root => "http://" + CONFIG["default_organisation_domain"],
      :credentials => {
        :dn => PUAVO_ETC.ldap_dn,
        :password => PUAVO_ETC.ldap_password }
    )

    @school = PuavoRest::School.new(
      :name => "Test School 1",
      :abbreviation => "testschool1"
    )
    @school.save!

    @group = PuavoRest::Group.new(
      :name => "Test group 1",
      :abbreviation => "testgroup1",
      :school_dn => @school.dn
    )
    @group.save!

  end

  describe "group creation" do

    it "has Fixnum id" do
      assert_equal Fixnum, @group.id.class
    end

  end

  describe "group updating" do

    before(:each) do
      @school = School.create(
        :cn => "gryffindor",
        :displayName => "Gryffindor",
        :puavoSchoolHomePageURL => "schoolhomepage.example"
      )
      @user = PuavoRest::User.new(
        :first_name => "Heli",
        :last_name => "Kopteri",
        :username => "heli",
        :roles => ["staff"],
        :email => "heli.kopteri@example.com",
        :school_dns => [@school.dn.to_s],
        :password => "userpwlonger"
      )
      @user.save!

    end

    it "add new members" do

      @group.add_member(@user)
      @group.save!

      reloaded_group = PuavoRest::Group.by_dn!(@group.dn)

      assert_equal reloaded_group.member_usernames.include?(@user.username), true
      assert_equal reloaded_group.member_dns.include?(@user.dn), true
    end
  end
end
