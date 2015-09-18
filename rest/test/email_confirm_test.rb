require_relative "./helper"

describe PuavoRest::EmailConfirm do

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

    @user = User.new(
      :givenName => "Bob",
      :sn  => "Brown",
      :uid => "bob",
      :puavoEduPersonAffiliation => "student",
      :mail => "bob@example.com",
      :role_ids => [@role.puavoId]
    )

    @user.set_password "secret"
    @user.puavoSchool = @school.dn
    @user.role_ids = [
      Role.find(:first, {
        :attribute => "displayName",
        :value => "Maintenance"
      }).puavoId,
      @role.puavoId
    ]
    @user.save!

  end

  describe "POST /email_confirm" do
    it "send email message to user with url for email confirmation" do
      $mailer = Class.new do
        def self.options
          return @options
        end

        def self.send(args)
          @options = args
        end
      end

      post "/email_confirm", {
        "username" => "bob",
        "email" => "bob@example.com"
      }
      assert_200

      data = JSON.parse(last_response.body)
      assert_equal "successfully", data["status"]

      assert_equal "bob@example.com", $mailer.options[:to]
      assert_equal "Confirm your email address", $mailer.options[:subject]

      puts $mailer.options[:body].inspect
      jwt = $mailer.options[:body].match("https://example.opinsys.net/users/email_confirm/(.+)$")[1]
      jwt_data = JWT.decode(jwt, "barfoo")
      assert_equal "bob", jwt_data["username"]
      assert_equal "example.opinsys.net", jwt_data["organisation_domain"]
      assert_equal "bob@example.com", jwt_data["email"]
    end
  end

end
