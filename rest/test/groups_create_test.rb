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
      :type => "teaching group",
      :school_dn => @school.dn
    )
    @group.save!

    @group2 = PuavoRest::Group.new(
      :name => "Test group 2",
      :abbreviation => "testgroup2",
      :type => "administrative group",
      :school_dn => @school.dn
    )
    @group2.save!

    @group3 = PuavoRest::Group.new(
      :name => "Test group 3",
      :abbreviation => "testgroup3",
      :type => "administrative group",
      :school_dn => @school.dn
    )
    @group3.save!

    @user = PuavoRest::User.new(
      :first_name => "Bob",
      :last_name => "Brown",
      :username => "bob",
      :roles => ["admin"],
      :school_dns => [@school.dn.to_s],
      :password => "secret123"
    )
    @user.save!

  end

  describe "group creation" do

    it "has String id" do
      assert_equal String, @group.id.class
    end

    it "has type" do
      assert_equal "teaching group", @group.type
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

  describe "GET /v3/administrative_groups" do
    it "lists all administrative groups" do
      basic_authorize "bob", "secret123"
      get "/v3/administrative_groups"
      assert_200
      data = JSON.parse(last_response.body)

      assert_equal "Test group 2", data[0]["name"]
      assert_equal "Test group 3", data[1]["name"]
    end
  end
end
