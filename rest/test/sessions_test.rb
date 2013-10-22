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
    FileUtils.rm_rf CONFIG["ltsp_server_data_dir"]
    @school = School.create(
      :cn => "gryffindor",
      :displayName => "Gryffindor"
    )
    @device = create_device(
      :puavoDeviceImage => "ownimage",
      :puavoHostname => "athin",
      :macAddress => "bf:9a:8c:1b:e0:6a",
      :puavoSchool => @school.dn
    )
    @server1 = create_server(
      :puavoHostname => "server1",
      :macAddress => "bc:5f:f4:56:59:71"
    )
    @server2 = create_server(
      :puavoHostname => "server2",
      :macAddress => "bc:5f:f4:56:59:72"
    )
  end

  describe "load filter" do
    it "gives the most idle server" do
      put "/v3/ltsp_servers/server1",
        "load_avg" => "0.1",
        "cpu_count" => 2,
        "ltsp_image" => "image1"
      assert_200

      put "/v3/ltsp_servers/server2",
        "load_avg" => "0.9",
        "cpu_count" => 2,
        "ltsp_image" => "image2"
      assert_200

      post "/v3/sessions", { "hostname" => "athin" }, {
        "HTTP_AUTHORIZATION" => "Bootserver"
      }
      assert_200

      data = JSON.parse last_response.body
      assert_equal "server1", data["ltsp_server"]["hostname"]
    end
  end

  describe "old server filter" do
    it "filters out servers that are not updated recently" do
      put "/v3/ltsp_servers/server1",
        "load_avg" => "0.1",
        "cpu_count" => 2,
        "ltsp_image" => "image1"
      assert_200

      Timecop.travel 60 * 5

      put "/v3/ltsp_servers/server2",
        "load_avg" => "0.9",
        "cpu_count" => 2,
        "ltsp_image" => "image2"
      assert_200

      post "/v3/sessions", { "hostname" => "athin" }, {
        "HTTP_AUTHORIZATION" => "Bootserver"
      }
      assert_200

      data = JSON.parse last_response.body
      assert_equal(
        "server2", data["ltsp_server"]["hostname"],
        "server1 has less load but server2 must be given because server1 has timed out"
      )
    end
  end

  describe "prefered server on client" do
    it "is served first" do

      create_device(
        :puavoHostname => "thin-with-prefered-server",
        :puavoPreferredServer => @server2.dn,
        :macAddress => "bf:9a:8c:1b:e0:6a",
        :puavoSchool => @school.dn
      )

      put "/v3/ltsp_servers/server1",
        "load_avg" => "0.1",
        "cpu_count" => 2,
        "ltsp_image" => "image1"
      assert_200
      put "/v3/ltsp_servers/server2",
        "load_avg" => "0.9",
        "cpu_count" => 2,
        "ltsp_image" => "image2"
      assert_200

      post "/v3/sessions", { "hostname" => "thin-with-prefered-server" }, {
        "HTTP_AUTHORIZATION" => "Bootserver",
      }
      assert_200

      data = JSON.parse last_response.body
      assert_equal(
        "server2", data["ltsp_server"]["hostname"],
        "server1 has less load but server2 must be given because server1 is prefered by the client"
      )

    end
  end



  describe "nonexistent device hostname" do
    it "gets 404" do
      post "/v3/sessions", { "hostname" => "nonexistent" }, {
        "HTTP_AUTHORIZATION" => "Bootserver"
      }
      assert_equal 404, last_response.status
    end
  end

  describe "thin with own image" do
    it "uses it's own image" do
      create_server(
        :puavoHostname => "testserver",
        :macAddress => "bc:5f:f4:56:59:71"
      )
      put "/v3/ltsp_servers/testserver",
        "load_avg" => "0.5",
        "cpu_count" => 2,
        "ltsp_image" => "ownimage"
      assert_200

      create_device(
        :puavoDeviceImage => "ownimage",
        :puavoHostname => "thinwithimage",
        :macAddress => "bc:5f:f4:56:59:71",
        :puavoSchool => @school.dn
      )

      post "/v3/sessions", { "hostname" => "thinwithimage" }, {
        "HTTP_AUTHORIZATION" => "Bootserver"
      }
      data = JSON.parse last_response.body
      assert_equal data["ltsp_server"]["hostname"], "testserver"
    end
  end

  describe "thinclient with no own image" do
    it "uses image from school" do
      create_server(
        :puavoHostname => "school-image-server",
        :macAddress => "bc:5f:f4:56:59:71"
      )
      put "/v3/ltsp_servers/school-image-server",
        "load_avg" => "0.8",
        "cpu_count" => 2,
        "ltsp_image" => "schoolsimage"
      assert_200
      @school.puavoDeviceImage = "schoolsimage"
      @school.save!

      create_device(
        :puavoHostname => "thinnoimage",
        :macAddress => "bc:5f:f4:56:59:72",
        :puavoSchool => @school.dn
      )

      post "/v3/sessions", { "hostname" => "thinnoimage" }, {
        "HTTP_AUTHORIZATION" => "Bootserver"
      }
      data = JSON.parse last_response.body
      assert_equal  "school-image-server", data["ltsp_server"]["hostname"]
    end
  end

  describe "organisation level image" do
    it "is given to other clients" do
      create_server(
        :puavoHostname => "organisation-image-server",
        :macAddress => "bc:5f:f4:56:59:71"
      )
      put "/v3/ltsp_servers/organisation-image-server",
        "load_avg" => "0.8",
        "cpu_count" => 2,
        "ltsp_image" => "organisationimage"
      assert_200
      create_device(
        :puavoHostname => "thinnoimage",
        :macAddress => "bc:5f:f4:56:59:72",
        :puavoSchool => @school.dn
      )

      test_organisation = LdapOrganisation.first
      test_organisation.puavoDeviceImage = "organisationimage"
      test_organisation.save!

      post "/v3/sessions", { "hostname" => "thinnoimage" }, {
        "HTTP_AUTHORIZATION" => "Bootserver"
      }
      assert_200
      data = JSON.parse last_response.body
      assert_equal  "organisation-image-server", data["ltsp_server"]["hostname"]
    end
  end

  describe "no image at all" do
    it "gets the most idle server" do
      create_server(
        :puavoHostname => "most-idle-server",
        :macAddress => "bc:5f:f4:56:59:71"
      )
      put "/v3/ltsp_servers/most-idle-server",
        "load_avg" => "0.0",
        "cpu_count" => 2,
        "ltsp_image" => "someimage"
      assert_200

      create_device(
        :puavoHostname => "thinnoimage",
        :macAddress => "bc:5f:f4:56:59:72",
        :puavoSchool => @school.dn
      )

      post "/v3/sessions", { "hostname" => "thinnoimage" }, {
        "HTTP_AUTHORIZATION" => "Bootserver"
      }
      assert_200

      data = JSON.parse last_response.body
      assert_equal  "most-idle-server", data["ltsp_server"]["hostname"]
    end
  end

  describe "GET sessions" do
    before(:each) do
      create_server(
        :puavoHostname => "most-idle-server",
        :macAddress => "bc:5f:f4:56:59:71"
      )
      put "/v3/ltsp_servers/most-idle-server",
        "load_avg" => "0.0",
        "cpu_count" => 2,
        "ltsp_image" => "someimage"

      create_device(
        :puavoHostname => "thinnoimage",
        :macAddress => "bc:5f:f4:56:59:72",
        :puavoSchool => @school.dn
      )
    end

    describe "GET and DELETE" do
      before(:each) do
        post "/v3/sessions", { "hostname" => "thinnoimage" }, {
          "HTTP_AUTHORIZATION" => "Bootserver"
        }
        assert_200

        @post_data = JSON.parse last_response.body
        assert @post_data["uuid"], "has uuid"
      end

      it "can be fetched with uuid only" do
        get "/v3/sessions/#{ @post_data["uuid"] }", {}, {
          "HTTP_AUTHORIZATION" => "Bootserver"
        }
        get_data = JSON.parse last_response.body
        assert_200
        assert_equal @post_data["uuid"], get_data["uuid"]
      end

      it "can be deleted with uuid only" do
        delete "/v3/sessions/#{ @post_data["uuid"] }", {}, {
          "HTTP_AUTHORIZATION" => "Bootserver"
        }
        assert_200

        get "/v3/sessions/#{ @post_data["uuid"] }", {}, {
          "HTTP_AUTHORIZATION" => "Bootserver"
        }
        assert_equal 404, last_response.status
      end


      it "responds 404 for unknown sessions" do
        get "/v3/sessions/doesnotexists", {}, {
          "HTTP_AUTHORIZATION" => "Bootserver"
        }
        assert_equal 404, last_response.status
        data = JSON.parse(last_response.body)
        assert data["error"], "Must have error"
        assert_equal "NotFound", data["error"]["code"]
      end


      it "DELETE responds 404 for bad uuids" do
        delete "/v3/sessions/baduid", {}, {
          "HTTP_AUTHORIZATION" => "Bootserver"
        }
        assert_equal 404, last_response.status
      end

    end


    it "all sessions can be fetched from index" do
      create_device(
        :puavoHostname => "thin1",
        :macAddress => "bc:5f:f4:56:59:72",
        :puavoSchool => @school.dn
      )
      create_device(
        :puavoHostname => "thin2",
        :macAddress => "bc:5f:f4:56:59:73",
        :puavoSchool => @school.dn
      )

      post "/v3/sessions", { "hostname" => "thin1" }, {
        "HTTP_AUTHORIZATION" => "Bootserver"
      }
      assert_200

      post "/v3/sessions", { "hostname" => "thin2" }, {
        "HTTP_AUTHORIZATION" => "Bootserver"
      }
      assert_200

      get "/v3/sessions"
      data = JSON.parse last_response.body

      assert_equal Array, data.class
      assert_equal 2, data.size
    end

  end

  describe "LTSP server school limit" do
    before(:each) do
      ltsp_school = School.create(
        :cn => "ltspschool",
        :displayName => "School with private LTSP server"
      )

      create_server(
        :puavoHostname => "normalserver",
        :macAddress => "42:67:8d:2b:d1:82"
      )

      create_server(
        :puavoHostname => "limitedserver",
        :macAddress => "76:62:8f:79:9a:a3",
        :puavoSchool => [ltsp_school.dn]
      )

      create_device(
        :puavoHostname => "limitedschooldevice",
        :macAddress => "38:f5:f8:35:4c:4d",
        :puavoSchool => ltsp_school.dn
      )

      create_device(
        :puavoHostname => "normalschooldevice",
        :macAddress => "79:61:37:31:d1:ba",
        :puavoSchool => @school.dn
      )

    end

    it "must not serve limited servers to others" do
      # Limited server has less load
      put "/v3/ltsp_servers/limitedserver",
        "load_avg" => "0.2",
        "cpu_count" => 2,
        "ltsp_image" => "someimage"
      assert_200

      put "/v3/ltsp_servers/normalserver",
        "load_avg" => "0.8",
        "cpu_count" => 2,
        "ltsp_image" => "anotherimage"
      assert_200

      post "/v3/sessions", { "hostname" => "normalschooldevice" }, {
        "HTTP_AUTHORIZATION" => "Bootserver"
      }
      data = JSON.parse last_response.body

      # But the client will get normalserver regardless
      assert_equal "normalserver", data["ltsp_server"]["hostname"]
    end

    it "must prefer servers to schools they are prefered to" do
      put "/v3/ltsp_servers/limitedserver",
        "load_avg" => "0.9",
        "cpu_count" => 2,
        "ltsp_image" => "someimage"

      # Normal server has less load
      put "/v3/ltsp_servers/normalserver",
        "load_avg" => "0.1",
        "cpu_count" => 2,
        "ltsp_image" => "anotherimage"

      post "/v3/sessions", { "hostname" => "limitedschooldevice" }, {
        "HTTP_AUTHORIZATION" => "Bootserver"
      }
      data = JSON.parse last_response.body

      # But client will get limitedserver because it is forced to its school
      assert_equal "limitedserver", data["ltsp_server"]["hostname"]
    end

  end

  describe "printers" do

    before(:each) do
      @bootserver = Server.new
      @bootserver.attributes = {
        :puavoHostname => "boot",
        :macAddress => "27:b0:59:3c:ac:a4",
        :puavoDeviceType => "bootserver"
      }
      @bootserver.save!

      @printer1 = create_printer(@bootserver, "printer1")
      @wireless_printer = create_printer(@bootserver, "wireless printer")

      @school.add_printer(@printer1)
      @school.add_wireless_printer(@wireless_printer)

      @group_printer = create_printer(@bootserver, "group printer")
      @group = Group.new
      @group.cn = "group1"
      @group.displayName = "Group 1"
      @group.puavoSchool = @school.dn
      @group.save!
      @group.add_printer(@group_printer)

      @device_printer = create_printer(@bootserver, "device printer")
      @device.add_printer(@device_printer)

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
        :mail => "bob@example.com"
      )
      @user.set_password "secret"
      @user.puavoSchool = @school.dn
      @user.role_ids = [@role.puavoId]
      @user.save!


      put "/v3/ltsp_servers/server1",
        "load_avg" => "0.1",
        "cpu_count" => 2,
        "ltsp_image" => "image1"

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
      @device.add_printer(@dupprinter)
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
      assert_equal Fixnum, data["user"]["groups"].first["gid_number"].class, "gid_number must be number"
    end


  end

end
