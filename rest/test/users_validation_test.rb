require_relative "./helper"
require_relative "../lib/ldapmodel"

describe LdapModel do

  describe "user validation" do

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
    end

    it "cannot create users with the same usernames" do
      user = PuavoRest::User.new(
        :first_name => "Heli",
        :last_name => "Kopteri",
        :username => "heli",
        :roles => ["staff"],
        :email => "heli.kopteri2@example.com",
        :school_dns => [@school.dn.to_s],
        :password => "userpassswordislong",

        :login_shell => "/bin/bash"
      )

      err = assert_raises ValidationError do
        user.save!
      end

      username_error = err.as_json[:error][:meta][:invalid_attributes][:username].first
      assert username_error
      assert_equal :username_not_unique, username_error[:code]
      assert_equal "username=heli is not unique", username_error[:message]
      assert_equal @user.id, PuavoRest::IdPool.last_id("puavoNextId").to_i

    end

    it "model can be validated only" do
      user = PuavoRest::User.new(
        :first_name => "Heli",
        :last_name => "Kopteri",
        :username => "heli",
        :roles => ["staff"],
        :email => "heli.kopteri@example.com",
        :school_dns => [@school.dn.to_s],
        :password => "userpassswordislong"
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
        :first_name => "Foo",
        :last_name => "Bar",
        :username => "foo",
        :roles => ["staff"],
        :email => "foo@example.com",
        :school_dns => [@school.dn.to_s],
        :password => "userpassswordislong"
      )

      user.validate!
      assert !PuavoRest::User.by_username("foo"), "the user cannot be found because it is not saved"
    end

    it "can be accessed over http" do
      basic_authorize "heli", "userpassswordislong"
      post "/v3/users_validate", {
        :first_name => "Heli",
        :last_name => "Kopteri",
        :username => "heli",
        :roles => ["staff"],
        :email => "heli.kopteri@example.com",
        :school_dns => [@school.dn.to_s],
        :password => "userpassswordislong"
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

    it "does not allow empty first name" do
      user = PuavoRest::User.new(
        :last_name => "Bar",
        :username => "foo",
        :roles => ["staff"],
        :email => "foo@example.com",
        :school_dns => [@school.dn.to_s],
        :password => "userpassswordislong"
      )

      err = assert_raises ValidationError do
        user.validate!
      end

      first_name_error = err.as_json[:error][:meta][:invalid_attributes][:first_name].first
      assert first_name_error
      assert_equal :first_name_empty, first_name_error[:code]
      assert_equal "First name is empty", first_name_error[:message]
    end

    it "does not allow empty last name" do
      user = PuavoRest::User.new(
        :first_name => "Foo",
        :username => "foo",
        :roles => ["staff"],
        :email => "foo@example.com",
        :school_dns => [@school.dn.to_s],
        :password => "userpassswordislong"
      )

      err = assert_raises ValidationError do
        user.validate!
      end

      error = err.as_json[:error][:meta][:invalid_attributes][:last_name].first
      assert error
      assert_equal :last_name_empty, error[:code]
      assert_equal "Last name is empty", error[:message]
    end

    it "does not allow short passwords" do
      user = PuavoRest::User.new(
        :first_name => "Foo",
        :last_name => "Bar",
        :username => "foo",
        :roles => ["staff"],
        :email => "foo@example.com",
        :school_dns => [@school.dn.to_s],
        :password => "short"
      )

      err = assert_raises ValidationError do
        user.validate!
      end

      error = err.as_json[:error][:meta][:invalid_attributes][:password].first
      assert error
      assert_equal :password_too_short, error[:code]
      assert_equal "Password must have at least 8 characters", error[:message]
    end

    it "do not allow 'root' as username" do
      user = PuavoRest::User.new(
        :first_name => "Foo",
        :last_name => "Bar",
        :username => "root",
        :roles => ["staff"],
        :email => "foo@example.com",
        :school_dns => [@school.dn.to_s],
        :password => "sdafdsdfsadfsadsf"
      )

      err = assert_raises ValidationError do
        user.validate!
      end

      error = err.as_json[:error][:meta][:invalid_attributes][:username].first
      assert error
      assert_equal :username_not_allowed, error[:code]
      assert_equal "Username not allowed", error[:message]
    end

    it "do not allow adm- prefix in usernames" do
      user = PuavoRest::User.new(
        :first_name => "Foo",
        :last_name => "Bar",
        :username => "adm-foo",
        :roles => ["staff"],
        :email => "foo@example.com",
        :school_dns => [@school.dn.to_s],
        :password => "sdafdsdfsadfsadsf"
      )

      err = assert_raises ValidationError do
        user.validate!
      end

      error = err.as_json[:error][:meta][:invalid_attributes][:username].first
      assert error
      assert_equal :username_not_allowed, error[:code]
      assert_equal "'adm-' prefix is not allowed", error[:message]

    end

    [ # deny these
      "1foo",
      " foo",
      "foo ",
      "Foo",
      "foo bar",
      "-foo",
      ".foo",
      "foo_bar",
      "FOO",
    ].each do |invalid_username|
      it "denies invalid username '#{ invalid_username }'" do
        user = PuavoRest::User.new(
          :first_name => "Foo",
          :last_name => "Bar",
          :username => invalid_username,
          :roles => ["staff"],
          :email => "foo@example.com",
          :school_dns => [@school.dn.to_s],
          :password => "sdafdsdfsadfsadsf"
        )

        err = assert_raises ValidationError do
          user.validate!
        end

        error = err.as_json[:error][:meta][:invalid_attributes][:username].first
        assert error, "must not allow username '#{ invalid_username }'"
        assert_equal :username_invalid, error[:code]
        assert_equal "Invalid username. Allowed characters a-z, 0-9, dot and dash. Also it must begin with a letter", error[:message]
      end

    end


    it "do not allow too short username" do
      user = PuavoRest::User.new(
        :first_name => "Foo",
        :last_name => "Bar",
        :username => "ba",
        :roles => ["staff"],
        :email => "foo@example.com",
        :school_dns => [@school.dn.to_s],
        :password => "sdafdsdfsadfsadsf"
      )

      err = assert_raises ValidationError do
        user.validate!
      end

      error = err.as_json[:error][:meta][:invalid_attributes][:username].first
      assert error
      assert_equal :username_too_short, error[:code]
      assert_equal "Username too short", error[:message]

    end

    it "do not allow too long username" do
      user = PuavoRest::User.new(
        :first_name => "Foo",
        :last_name => "Bar",
        :username => "a"*300,
        :roles => ["staff"],
        :email => "foo@example.com",
        :school_dns => [@school.dn.to_s],
        :password => "sdafdsdfsadfsadsf"
      )

      err = assert_raises ValidationError do
        user.validate!
      end

      error = err.as_json[:error][:meta][:invalid_attributes][:username].first
      assert error
      assert_equal :username_too_long, error[:code]
      assert_equal "Username too long", error[:message]

    end




  end
end
