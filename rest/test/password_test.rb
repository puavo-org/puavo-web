require_relative "./helper"

describe PuavoRest::Password do

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
      :type         => 'administrative group')
    @group.save!

    maintenance_group = Group.find(:first,
                                   :attribute => 'cn',
                                   :value     => 'maintenance')
    @student = PuavoRest::User.new(
      :email              => 'bob@example.com',
      :first_name         => 'Bob',
      :last_name          => 'Brown',
      :password           => 'secret',
      :preferred_language => 'en',
      :roles              => [ 'student' ],
      :school_dns         => [ @school.dn.to_s ],
      :username           => 'bob',
    )
    @student.save!
    # XXX weird that this must be here
    @student.administrative_groups = [ maintenance_group.id, @group.id ]

    @teacher = PuavoRest::User.new(
      :email              => 'teacher@example.com',
      :first_name         => 'Test',
      :last_name          => 'Teacher',
      :password           => 'foobar',
      :preferred_language => 'en',
      :roles              => [ 'teacher' ],
      :school_dns         => [ @school.dn.to_s ],
      :username           => 'teacher',
    )
    @teacher.save!
    @teacher.administrative_groups = [ maintenance_group.id, @group.id ]
  end

  describe "Test the school users list" do
    it "A student cannot view the school users list" do
      basic_authorize "bob", "secret"
      get "/v3/my_school_users"
      assert_equal 401, last_response.status
    end

    it "A teacher can view the school users list" do
      basic_authorize "teacher", "foobar"
      get "/v3/my_school_users"
      assert_equal 200, last_response.status
    end

    it "Ensure Bob Brown is listed on the page" do
      basic_authorize "teacher", "foobar"
      get "/v3/my_school_users"
      assert_equal 200, last_response.status

      # There's only one student, so this works... kinda
      # (If there were two students, there'd be 8 TD elements in the array)
      parts = parse_html(last_response.body).css(".users td")
      assert_equal 4, parts.length
      assert_equal "Brown", parts[0].content
      assert_equal "Bob", parts[1].content
      assert_equal "bob", parts[2].content
    end

    it "Ensure the group is listed" do
      basic_authorize "teacher", "foobar"
      get "/v3/my_school_users"
      assert_equal 200, last_response.status

      # Again there's only one group
      parts = parse_html(last_response.body).css("div#groupsList h1")

      assert_equal 1, parts.length
      assert_equal "No teaching group", parts[0].content
    end
  end

  describe "Mailer class" do
    it "initialize and correct options" do
      email = PuavoRest::Mailer.new
      assert_equal({ :via => :smtp,
                     :from => "Puavo Org <no-reply@puavo.net>",
                     :via_options => {
                       :address => CONFIG["password_management"]["smtp"]["via_options"][:address],
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
        "request_id" => "ABCDEFGHIJ",   # I'm not sure if this is really needed
        "username" => "bob",
        "email" => "bob@example.com",
      }
      assert_200

      data = JSON.parse(last_response.body)
      assert_equal "successfully", data["status"]

      jwt = $mailer.options[:body].match("https://example.puavo.net/users/password/(.+)/reset$")[1]
      jwt_decode_data = JWT.decode(jwt, "foobar")
      jwt_data = jwt_decode_data[0] # jwt_decode_data is [payload, header]

      assert_equal "bob@example.com", $mailer.options[:to]
      assert_equal "Reset your password", $mailer.options[:subject]
      assert_equal "bob", jwt_data["uid"]
      assert_equal "example.puavo.net", jwt_data["domain"]
    end
  end

end
