require_relative "./helper"

describe PuavoRest::EmailConfirm do

  before(:each) do
    Puavo::Test.clean_up_ldap
    setup_ldap_admin_connection()

    @school = School.create(
      :cn => "gryffindor",
      :displayName => "Gryffindor",
      :puavoSchoolHomePageURL => "schoolhomepage.example"
    )

    @group = PuavoRest::Group.new(
      :abbreviation => 'group1',
      :name         => 'Group 1',
      :school_dn    => @school.dn.to_s,
      :type         => 'teaching group')
    @group.save!

    maintenance_group = Group.find(:first,
                                   :attribute => 'cn',
                                   :value     => 'maintenance')
    @user = PuavoRest::User.new(
      :email      => 'bob@example.com',
      :first_name => 'Bob',
      :last_name  => 'Brown',
      :roles      => [ 'student' ],
      :school_dns => [ @school.dn.to_s ],
      :username   => 'bob',
    )
    @user.save!

    # XXX weird that these must be here
    @user.administrative_groups = [ maintenance_group.id ]
    @user.teaching_group = @group
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

      jwt = $mailer.options[:body].match("https://example.puavo.net/users/email_confirm/(.+)$")[1]
      jwt_decode_data = JWT.decode(jwt, "barfoo")
      jwt_data = jwt_decode_data[0] # jwt_decode_data is [payload, header]
      assert_equal "bob", jwt_data["username"]
      assert_equal "example.puavo.net", jwt_data["organisation_domain"]
      assert_equal "bob@example.com", jwt_data["email"]
    end
  end

end
