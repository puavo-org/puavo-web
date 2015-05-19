require_relative "./helper"
require_relative "../lib/ldapmodel"
require_relative "../resources/roles"

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
        :object_classes => ["top", "posixAccount", "inetOrgPerson", "puavoEduPerson", "sambaSamAccount", "eduPerson"],
        :first_name => "Heli",
        :last_name => "Kopteri",
        :username => "heli",
        :roles => ["staff"],
        :email => "heli.kopteri@example.com",
        :school_dns => [@school.dn.to_s],
        :password => "userpw"
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

        :login_shell => "/bin/bash"
      )

      err = assert_raises ValidationError do
        user.save!
      end

      username_error = err.as_json[:error][:meta][:invalid_attributes][:username].first
      assert username_error
      assert_equal :username_not_unique, username_error[:code]
      assert_equal "username=heli is not unique", username_error[:message]
    end

    describe "validation" do

      it "model can be validated only" do
        user = PuavoRest::User.new(
          :object_classes => ["top", "posixAccount", "inetOrgPerson", "puavoEduPerson", "sambaSamAccount", "eduPerson"],
          :first_name => "Heli",
          :last_name => "Kopteri",
          :username => "heli",
          :roles => ["staff"],
          :email => "heli.kopteri@example.com",
          :school_dns => [@school.dn.to_s],
          :password => "userpw"
        )

        err = assert_raises ValidationError do
          user.validate!
        end

        username_error = err.as_json[:error][:meta][:invalid_attributes][:username].first
        assert username_error
        assert_equal :username_not_unique, username_error[:code]
        assert_equal "username=heli is not unique", username_error[:message]
      end

      it "on successful validation the model is not saved" do
        user = PuavoRest::User.new(
          :object_classes => ["top", "posixAccount", "inetOrgPerson", "puavoEduPerson", "sambaSamAccount", "eduPerson"],
          :first_name => "Foo",
          :last_name => "Bar",
          :username => "foo",
          :roles => ["staff"],
          :email => "foo@example.com",
          :school_dns => [@school.dn.to_s],
          :password => "userpw"
        )

        user.validate!
        assert !PuavoRest::User.by_username("foo"), "the user cannot be found because it is not saved"
      end

      it "can be accessed over http" do
        basic_authorize "heli", "userpw"
        post "/v3/users_validate", {
          :first_name => "Heli",
          :last_name => "Kopteri",
          :username => "heli",
          :roles => ["staff"],
          :email => "heli.kopteri@example.com",
          :school_dns => [@school.dn.to_s],
          :password => "userpw"
        }

        assert_equal 400, last_response.status
        data = JSON.parse last_response.body
        assert_equal "ValidationError", data["error"]["code"]

        assert(
          data["error"]["meta"]["invalid_attributes"]["username"],
          "username is duplicate"
        )
        assert_equal(
          "username_not_unique",
          data["error"]["meta"]["invalid_attributes"]["username"][0]["code"]
        )

        assert(
          data["error"]["meta"]["invalid_attributes"]["email"],
          "email is duplicate"
        )
        assert_equal(
          "email_not_unique",
          data["error"]["meta"]["invalid_attributes"]["email"][0]["code"]
        )

      end

    end
  end
end
