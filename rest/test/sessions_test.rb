require_relative "./helper"

describe PuavoRest::Sessions do

  before(:each) do
    Puavo::Test.clean_up_ldap
    FileUtils.rm_rf PuavoRest::CONFIG["ltsp_server_data_dir"]
    @school = School.create(
      :cn => "gryffindor",
      :displayName => "Gryffindor"
    )
    create_device(
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

      post "/v3/sessions", "hostname" => "athin"
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

      post "/v3/sessions", "hostname" => "athin"
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

      post "/v3/sessions", "hostname" => "thin-with-prefered-server"
      assert_200

      data = JSON.parse last_response.body
      assert_equal(
        "server2", data["ltsp_server"]["hostname"],
        "server1 has less load but server2 must be given because server1 is prefered by the client"
      )

    end
  end



  describe "nonexistent device hostname" do
    it "gets 400" do
      post "/v3/sessions", "hostname" => "nonexistent"
      assert_equal 400, last_response.status
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

      post "/v3/sessions", "hostname" => "thinwithimage"
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

      post "/v3/sessions", "hostname" => "thinnoimage"
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

      post "/v3/sessions", "hostname" => "thinnoimage"
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

      post "/v3/sessions", "hostname" => "thinnoimage"
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

    it "can be fetched with GET" do
      post "/v3/sessions", "hostname" => "thinnoimage"
      assert_200

      post_data = JSON.parse last_response.body
      assert post_data["uuid"], "has uuid"

      get "/v3/sessions/#{ post_data["uuid"] }"
      get_data = JSON.parse last_response.body
      assert_equal post_data["uuid"], get_data["uuid"]
    end

    it "get 404 for nonexistent sessions" do
      get "/v3/sessions/doesnotexists"
      assert_equal 404, last_response.status
      data = JSON.parse(last_response.body)
      assert_equal "unknown session uuid 'doesnotexists'", data["error"]["message"]
    end

    it "can be deleted with DELETE" do
      post "/v3/sessions", "hostname" => "thinnoimage"
      assert_200

      data = JSON.parse last_response.body

      delete "/v3/sessions/#{ data["uuid"] }"
      assert_200

      get "/v3/sessions/#{ data["uuid"] }"
      assert_equal 404, last_response.status
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

      post "/v3/sessions", "hostname" => "thin1"
      assert_200

      post "/v3/sessions", "hostname" => "thin2"
      assert_200

      get "/v3/sessions"
      data = JSON.parse last_response.body

      assert_equal 2, data.size
      data.each do |s|
        assert s["ltsp_server"], "have ltsp server"
      end
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

      post "/v3/sessions", "hostname" => "normalschooldevice"
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

      post "/v3/sessions", "hostname" => "limitedschooldevice"
      data = JSON.parse last_response.body

      # But client will get limitedserver because it is forced to its school
      assert_equal "limitedserver", data["ltsp_server"]["hostname"]
    end

  end

end
