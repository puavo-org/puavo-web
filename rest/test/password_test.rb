require_relative "./helper"

describe PuavoRest::Password do

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

  describe "Mailer class" do
    it "initialize and correct options" do
      email = PuavoRest::Mailer.new
      assert_equal({ :via => :smtp,
                     :from => "Opinsys <no-reply@opinsys.fi>",
                     :via_options => {
                       :address => "localhost",
                       :port => 25,
                       :enable_starttls_auto => false
                     }
                   },
                   email.options )


    end

  end

  describe "POST /password/send_token" do
    it "send email message to user with url for reseting password" do
      $mailer = Class.new do
        def self.options
          return @options
        end

        def self.send(args)
          @options = args
        end
      end

      post "/password/send_token", {
        "username" => "bob"
      }
      assert_200

      data = JSON.parse(last_response.body)
      assert_equal "successfully", data["status"]

      jwt = $mailer.options[:body].match("https://example.opinsys.net/users/password/(.+)/reset$")[1]
      jwt_data = JWT.decode(jwt, "foobar")

      assert_equal "bob@example.com", $mailer.options[:to]
      assert_equal "Reset your password", $mailer.options[:subject]
      assert_equal "bob", jwt_data["username"]
      assert_equal "example.opinsys.net", jwt_data["organisation_domain"]
    end
  end

end
