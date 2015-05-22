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
        :password => "userpw"
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

    it "model can be validated only" do
      user = PuavoRest::User.new(
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
