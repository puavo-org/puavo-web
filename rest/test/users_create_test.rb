require_relative "./helper"
require_relative "../lib/ldapmodel"

describe LdapModel do

  describe "user creation" do

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

      @role = Role.new
      @role.displayName = "Some role"
      @role.puavoSchool = @school.dn
      @role.groups << @group
      @role.save!

      LdapModel.setup(
        :organisation => PuavoRest::Organisation.default_organisation_domain!,
        :rest_root => "http://" + CONFIG["default_organisation_domain"],
        :credentials => {
          :dn => PUAVO_ETC.ldap_dn,
          :password => PUAVO_ETC.ldap_password }
      )

      @user = PuavoRest::User.new(
        :first_name => "Heli",
        :last_name => "Kopteri",
        :username => "heli",
        :roles => ["staff"],
        :email => "heli.kopteri@example.com",
        :school_dns => [@school.dn.to_s],
        :password => "userpassswordislong"
      )
      @user.save!

      @teaching_group = PuavoRest::Group.new(
        :name => "5A",
        :abbreviation => "gryffindor-5a",
        :type => "teaching group",
        :school_dn => @school.dn.to_s
      )
      @teaching_group.save!

      @year_class = PuavoRest::Group.new(
        :name => "5",
        :abbreviation => "gryffindor-5a",
        :type => "year class",
        :school_dn => @school.dn.to_s
      )
      @year_class.save!

    end

    it "has Fixnum id" do
      # FIXME: should be String
      assert_equal Fixnum, @user.id.class
    end

    it "has dn" do
      assert @user.dn, "model got dn"
    end

    it "has email" do
      assert_equal @user.email, "heli.kopteri@example.com"
    end

    it "has home directory" do
      assert_equal "/home/gryffindor/heli", @user.home_directory
    end

    it "has gid_number from school" do
      assert_equal @school.gidNumber, @user.gid_number
    end

    it "has displayName ldap value" do
      assert_equal ["Heli Kopteri"], @user.get_raw(:displayName)
    end

    it "can be fetched by dn" do
      assert PuavoRest::User.by_dn!(@user.dn), "model can be found by dn"
    end

    it "has school" do
      assert_equal "Gryffindor", @user.schools.first.name
    end


    it "has internal samba attributes" do
      assert_equal ["[U]"], @user.get_raw(:sambaAcctFlags)

      samba_sid = @user.get_raw(:sambaSID)
      assert samba_sid
      assert samba_sid.first
      assert_equal "S", samba_sid.first.first

      samba_primary_group_sid = @user.get_raw(:sambaSID)
      assert samba_primary_group_sid
      assert samba_primary_group_sid.first
      assert_equal "S", samba_primary_group_sid.first.first

      samba_group = PuavoRest::SambaGroup.by_attr!(:name, "Domain Users")
      assert(
        samba_group.members.include?(@user.username),
        "Samba group 'Domain users' includes the username"
      )
    end

    it "can add secondary emails" do
      @user.secondary_emails = ["heli.another@example.com"]
      @user.save!

      assert_equal @user.email, "heli.kopteri@example.com"
      assert_equal @user.secondary_emails, ["heli.another@example.com"]

      user = PuavoRest::User.by_dn!(@user.dn)
      assert_equal user.email, "heli.kopteri@example.com"
      assert_equal user.secondary_emails, ["heli.another@example.com"]
    end

    it "can change primary email without affecting secondary emails" do
      @user.secondary_emails = ["heli.another@example.com"]
      @user.save!

      @user.email = "newemail@example.com"
      @user.save!

      assert_equal @user.email, "newemail@example.com"
      assert_equal @user.secondary_emails, ["heli.another@example.com"]

      user = PuavoRest::User.by_dn!(@user.dn)
      assert_equal user.email, "newemail@example.com"
      assert_equal user.secondary_emails, ["heli.another@example.com"]
    end

    it "can authenticate using the username and password" do
      basic_authorize "heli", "userpassswordislong"
      get "/v3/whoami"
      assert_200
      data = JSON.parse(last_response.body)
      assert_equal "heli", data["username"]
    end

    it "can change the password" do
      user = PuavoRest::User.by_dn!(@user.dn)
      user.password = "newlongpassword"
      user.save!

      basic_authorize "heli", "userpassswordislong"
      get "/v3/whoami"
      assert_equal 401, last_response.status, "old password is rejected"

      basic_authorize "heli", "newlongpassword"
      get "/v3/whoami"
      assert_200
    end

    it "does not break active ldap" do
      user = User.new(
        :givenName => "Mark",
        :sn  => "Hamil",
        :uid => "mark",
        :puavoEduPersonAffiliation => "student",
        :puavoLocale => "en_US.UTF-8",
        :mail => ["mark@example.com"],
        :role_ids => [@role.puavoId]
      )

      user.set_password "secret"
      user.puavoSchool = @school.dn
      user.role_ids = [
        Role.find(:first, {
          :attribute => "displayName",
          :value => "Maintenance"
        }).puavoId,
        @role.puavoId
      ]
      user.save!

    end

    it "can add groups" do
      @user.teaching_group = @teaching_group
      @user.year_class = @year_class

      assert @teaching_group.member_dns.include?(@user.dn), "User is not group member"
      assert_equal @user.teaching_group.name, "5A"

      assert @year_class.member_dns.include?(@user.dn), "User is not group member"
      assert_equal @user.year_class.name, "5"
    end
  end
end
