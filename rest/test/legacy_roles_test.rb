
require_relative "./helper"
require_relative "../lib/ldapmodel"

describe LdapModel do

  describe "Legacy Role" do

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

      @other_role = Role.new
      @other_role.displayName = "Other role"
      @other_role.puavoSchool = @school.dn
      @other_role.groups << @group
      @other_role.save!

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
    end

    it "can be listed via http" do
      basic_authorize "cucumber", "cucumber"
      get "/v3/schools/#{ @school.id }/legacy_roles"
      assert_200
      data = JSON.parse(last_response.body)
      assert_equal 2, data.size
      assert_equal @role.id, data.first["id"]
      assert_equal [], data.first["member_usernames"]
    end


    it "can have more members from http post" do
      basic_authorize "cucumber", "cucumber"
      post "/v3/schools/#{ @school.id }/legacy_roles/#{ @role.id }/members", {
        "username" => @user.username
      }
      assert_200

      get "/v3/schools/#{ @school.id }/legacy_roles"
      assert_200
      data = JSON.parse(last_response.body)
      assert_equal ["heli"], data.first["member_usernames"]

    end

    it "can be replaced" do
      basic_authorize "cucumber", "cucumber"
      post "/v3/schools/#{ @school.id }/legacy_roles/#{ @role.id }/members", {
        "username" => @user.username
      }
      assert_200

      get "/v3/users/heli/legacy_roles"
      assert_200
      data = JSON.parse(last_response.body)
      assert_equal 1, data.size
      assert_equal "Some role", data.first["name"]

      put "/v3/users/heli/legacy_roles", {
        "ids" => [@other_role.id]
      }
      assert_200

      get "/v3/users/heli/legacy_roles"
      assert_200
      data = JSON.parse(last_response.body)
      assert_equal 1, data.size
      assert_equal "Other role", data.first["name"]


    end

  end
end
