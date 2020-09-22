require_relative "./helper"

def create_printer(server, name)
  printer = Printer.new
  printer.attributes = {
    :printerDescription => name,
    :printerLocation => "school2",
    :printerMakeAndModel => "foo",
    :printerType => "1234",
    :printerURI => "socket://baz",
    :puavoServer => server.dn,
  }
  printer.save!
  printer
end

describe PuavoRest::Sessions do
  before(:each) do
    Puavo::Test.clean_up_ldap
    PuavoRest::Session.local_store.flushdb
    @school = School.create(
      :cn => "gryffindor",
      :displayName => "Gryffindor",
      :puavoLocale => "fi_FI.UTF-8",
      :puavoSchoolHomePageURL => "gryffindor.example"
    )
    @athin = create_device(
      :puavoDeviceImage => "ownimage",
      :puavoHostname => "athin",
      :macAddress => "bf:9a:8c:1b:e0:6a",
      :puavoSchool => @school.dn
    )
    @afat = create_device(
      :puavoHostname => "afat",
      :macAddress => "00:60:2f:D5:F8:60",
      :puavoSchool => @school.dn,
      :puavoDeviceType => "fatclient"
    )
    @server = create_server(
      :macAddress      => 'bc:5f:f4:56:59:73',
      :puavoDeviceType => 'bootserver',
      :puavoHostname   => 'server',
      :puavoSchool     => @school.dn,
    )
    PuavoRest.test_boot_server_dn = @server.dn.to_s
  end

  describe "nonexistent device hostname" do
    it "gets 404" do
      post "/v3/sessions", { "hostname" => "nonexistent" }, {
        "HTTP_AUTHORIZATION" => "Bootserver"
      }
      assert_equal 404, last_response.status
    end
  end

  describe "With users" do
    before(:each) do
      @bootserver = Server.new
      @bootserver.attributes = {
        :puavoHostname => "boot",
        :macAddress => "27:b0:59:3c:ac:a4",
        :puavoDeviceType => "bootserver"
      }
      @bootserver.save!

      @group = Group.new
      @group.cn = "group1"
      @group.displayName = "Group 1"
      @group.puavoEduGroupType = 'teaching group'
      @group.puavoSchool = @school.dn
      @group.save!

      setup_ldap_admin_connection()
      @user = PuavoRest::User.new(
        :email          => 'bob@example.com',
        :first_name     => 'Bob',
        :last_name      => 'Brown',
        :password       => 'secret',
        :locale         => 'de_CH.UTF-8',
        :roles          => [ 'student' ],
        :school_dns     => [ @school.dn.to_s ],
        :teaching_group => @group.id,
        :username       => 'bob',
      )
      @user.save!
    end

    describe "session without device hostname" do
      it "can be created" do
        basic_authorize "bob", "secret"
        post "/v3/sessions"
        assert_200

        data = JSON.parse last_response.body
        assert data["device"].nil?, "has no device"
        assert data["user"], "has user"
        assert_equal "bob",  data["user"]["username"], "has user"
      end
    end

    describe "fat client sessions" do
      before(:each) do
        basic_authorize "bob", "secret"
        post "/v3/sessions", { "hostname" => "afat" }
        assert_200

        @data = JSON.parse last_response.body
      end

      it "fat clients have sessions" do
        assert_equal "example.puavo.net", @data["organisation"], "has organisation info"
        assert @data["device"], "has device"
        assert_equal "afat", @data["device"]["hostname"]
      end

      it "has homepage for user" do
        assert @data["user"]
        assert_equal "gryffindor.example", @data["user"]["homepage"]
      end

      it "has homepage for device" do
        assert @data["device"]
        assert_equal "gryffindor.example", @data["device"]["homepage"]
      end
    end

    describe "laptop sessions" do
      before(:each) do
        @laptop1 = create_device(
          :puavoHostname => "laptop1",
          :macAddress => "00:60:2f:D5:F9:61",
          :puavoSchool => @school.dn,
          :puavoDeviceType => "laptop"
        )

        basic_authorize "bob", "secret"
        post "/v3/sessions", {
          "hostname" => "laptop1",
          "device_dn" => @laptop1.dn.to_s,
          "device_password" => @laptop1.ldap_password }
        assert_200

        @data = JSON.parse last_response.body
      end

      it "laptops have sessions" do
        assert_equal "example.puavo.net", @data["organisation"], "has organisation info"
        assert @data["device"], "has device"
        assert_equal "laptop1", @data["device"]["hostname"]
      end

      it "has homepage for user" do
        assert @data["user"]
        assert_equal "gryffindor.example", @data["user"]["homepage"]
      end

      it "has homepage for device" do
        assert @data["device"]
        assert_equal "gryffindor.example", @data["device"]["homepage"]
      end
    end

    describe "preferred language attribute" do
      it "is given from school to guests" do
        post "/v3/sessions", { "hostname" => "afat" }, {
          "HTTP_AUTHORIZATION" => "Bootserver"
        }
        assert_200
        data = JSON.parse last_response.body

        assert data["user"].nil?, "User should be nil for guests"
        assert_equal "fi", data["preferred_language"]
        assert_equal "fi", data["device"]["preferred_language"]
        assert_equal "fi_FI.UTF-8", data["locale"]
        assert_equal "fi_FI.UTF-8", data["device"]["locale"]
      end

      it "is their own for authenticated users" do
        basic_authorize "bob", "secret"
        post "/v3/sessions", { "hostname" => "afat" }
        assert_200
        data = JSON.parse last_response.body

        assert_equal "de", data["user"]["preferred_language"]
        assert_equal "de", data["preferred_language"]
        assert_equal "de_CH.UTF-8", data["user"]["locale"]
        assert_equal "de_CH.UTF-8", data["locale"]
      end
    end

    describe "printers" do
      before(:each) do
        @printer1 = create_printer(@bootserver, "printer1")
        @wireless_printer = create_printer(@bootserver, "wireless printer")

        @school.add_printer(@printer1)
        @school.add_wireless_printer(@wireless_printer)

        @group_printer = create_printer(@bootserver, "group printer")
        @group.add_printer(@group_printer)

        @device_printer = create_printer(@bootserver, "device printer")
        @athin.add_printer(@device_printer)
      end

      it "are given to guest sessions" do
        post "/v3/sessions", { "hostname" => "athin" }, {
          "HTTP_AUTHORIZATION" => "Bootserver"
        }
        assert_200
        data = JSON.parse last_response.body

        assert data["printer_queues"], "must have printer queues"
        assert_equal data["printer_queues"].size, 3

        assert_equal data["printer_queues"][0]["description"], "device printer"
        assert_equal data["printer_queues"][1]["description"], "printer1"
        assert_equal data["printer_queues"][2]["description"], "wireless printer"
      end

      describe "for authenticated users" do
        before(:each) do
          basic_authorize "bob", "secret"
          post "/v3/sessions", "hostname" => "athin"
          assert_200
          @data = JSON.parse last_response.body
          assert @data["printer_queues"], "must have printer queues"

          assert @data["user"], "must have user data"
          assert_equal "bob", @data["user"]["username"], "username must be 'bob' because we authenticated as bob"
        end

        it "from groups are given to authenticated users" do
          assert_equal(@data["printer_queues"].select do |p|
            p["description"] == "group printer"
          end.size, 1)
        end

        it "from devices are given to authenticated users" do
          assert_equal(@data["printer_queues"].select do |p|
            p["description"] == "device printer"
          end.size, 1)
        end
      end

      it "for wireless users are given from /v3/devices/:hostname/wireless_printer_queues" do
        get "/v3/devices/athin/wireless_printer_queues", {}, {
          "HTTP_AUTHORIZATION" => "Bootserver"
        }
        assert_200
        data = JSON.parse last_response.body
        assert_equal data.size, 1
        printer = data.first
        assert_equal printer["description"], "wireless printer"
      end

      it "does not duplicate printers if they are in multiple sources" do
        @dupprinter = create_printer(@bootserver, "dupprinter")
        @athin.add_printer(@dupprinter)
        @school.add_printer(@dupprinter)

        basic_authorize "bob", "secret"
        post "/v3/sessions", "hostname" => "athin"
        assert_200

        data = JSON.parse(last_response.body)
        dn_set = Set.new
        data["printer_queues"].each do |pq|
          dn = pq["dn"].downcase
          assert !dn_set.include?(dn), "Duplicate printer queue: #{ pq.inspect }"
          dn_set.add(dn)
        end
      end

      it "group data is in user hash" do
        # TODO: should not be under printer tests
        basic_authorize "bob", "secret"
        post "/v3/sessions", "hostname" => "athin"
        assert_200
        data = JSON.parse(last_response.body)

        assert data["user"], "has user data"
        assert data["user"]["groups"], "has groups data"
        assert data["user"]["groups"].first["gid_number"], "groups have gid_numbers"

        school_group = data["user"]["groups"].select do |g|
          g["name"] == "Gryffindor"
        end.first

        assert school_group, "Has schools in groups list"
        assert_equal(
          "gryffindor",
          school_group["abbreviation"],
          "School groups has a gid number too"
        )
        assert school_group["gid_number"], "has a gid number"

        assert_equal Fixnum, data["user"]["groups"].first["gid_number"].class, "gid_number must be number"
      end
    end
  end
end
