require_relative "./helper"
require_relative "../lib/ldapmodel"
require_relative "../resources/roles"
require "syslog"

Syslog.open("lol", Syslog::LOG_PID,
                        Syslog::LOG_DAEMON | Syslog::LOG_LOCAL3)

describe LdapModel do

  describe "User created by LdapMode" do

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
        :object_classes => ["top", "posixAccount", "inetOrgPerson", "puavoEduPerson", "sambaSamAccount", "eduPerson"],
        :first_name => "Heli",
        :last_name => "Kopteri",
        :username => "heli",
        :roles => ["staff"],
        :email => "heli.kopteri@example.com",
        :school_dns => [@school.dn.to_s],
        :password => "userpw",

        :login_shell => "/bin/bash",
        :samba_sid => "S-1-5-21-17441224-59077026-93552251-219809"
      )
      @user.save!
    end

    it "has Fixnum id" do
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

    it "has displayName ldap value" do
      assert_equal ["Heli Kopteri"], @user.get_raw(:displayName)
    end

    it "can be fetched by dn" do
      assert PuavoRest::User.by_dn! @user.dn, "model can be found by dn"
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
      basic_authorize "heli", "userpw"
      get "/v3/whoami"
      assert_200
      data = JSON.parse(last_response.body)
      assert_equal "heli", data["username"]
    end

    it "can change the password" do
      user = PuavoRest::User.by_dn!(@user.dn)
      user.password = "newpw"
      user.save!

      basic_authorize "heli", "userpw"
      get "/v3/whoami"
      assert_equal 401, last_response.status, "old password is rejected"

      basic_authorize "heli", "newpw"
      get "/v3/whoami"
      assert_200
    end

    it "cannot create users with the same usernames" do
      user = PuavoRest::User.new(
        :object_classes => ["top", "posixAccount", "inetOrgPerson", "puavoEduPerson", "sambaSamAccount", "eduPerson"],
        :first_name => "Heli",
        :last_name => "Kopteri",
        :username => "heli",
        :roles => ["staff"],
        :email => "heli.kopteri2@example.com",
        :school_dns => [@school.dn.to_s],
        :password => "userpw",

        :login_shell => "/bin/bash",
        :samba_sid => "S-1-5-21-17441224-59077026-93552251-219802"
      )

      err = assert_raises ValidationError do
        user.save!
      end

      username_error = err.as_json[:error][:meta][:invalid_attributes][:username].first
      assert username_error
      assert_equal :username_not_unique, username_error[:code]
      assert_equal "Username is not unique", username_error[:message]
    end

  end
end
