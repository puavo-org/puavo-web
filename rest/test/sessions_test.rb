require_relative "./helper"

describe PuavoRest::Sessions do

  def create_device(attrs)
    @thin_with_image = Device.new
    @thin_with_image.classes = ["top", "device", "puppetClient", "puavoNetbootDevice"]
    @thin_with_image.puavoSchool = @school.dn
    # @thin_with_image.puavoDeviceImage = "ownimage"
    # @thin_with_image.puavoHostname = "thinwithimage"
    @thin_with_image.puavoDeviceType = "thinclient"
    @thin_with_image.macAddress = "bc:5f:f4:56:59:71"

    @thin_with_image.attributes = attrs
    @thin_with_image.save!
  end

  before(:each) do
    Puavo::Test.clean_up_ldap
    FileUtils.rm_rf PuavoRest::CONFIG["ltsp_server_data_dir"]
    @school = School.create(
      :cn => "gryffindor",
      :displayName => "Gryffindor"
    )
    put "/v3/ltsp_servers/otherserver",
      "load_avg" => "0.8",
      "cpu_count" => 2,
      "ltsp_image" => "otherimage"
  end

  describe "nonexistent device hostname" do
    it "gets 400" do
      post "/v3/sessions", "hostname" => "nonexistent"
      assert_equal 400, last_response.status
    end
  end

  describe "thin with own image" do
    it "uses it's own image" do
      put "/v3/ltsp_servers/testserver",
        "load_avg" => "0.5",
        "cpu_count" => 2,
        "ltsp_image" => "ownimage"

      create_device(
        :puavoDeviceImage => "ownimage",
        :puavoHostname => "thinwithimage",
        :macAddress => "bc:5f:f4:56:59:71"
      )

      post "/v3/sessions", "hostname" => "thinwithimage"
      data = JSON.parse last_response.body
      assert_equal data["ltsp_server"]["hostname"], "testserver"
    end
  end

  describe "thinclient with no own image" do
    it "uses image from school" do
      put "/v3/ltsp_servers/school-image-server",
        "load_avg" => "0.8",
        "cpu_count" => 2,
        "ltsp_image" => "schoolsimage"
      @school.puavoDeviceImage = "schoolsimage"
      @school.save!

      create_device(
        :puavoHostname => "thinnoimage",
        :macAddress => "bc:5f:f4:56:59:72"
      )

      post "/v3/sessions", "hostname" => "thinnoimage"
      data = JSON.parse last_response.body
      assert_equal  "school-image-server", data["ltsp_server"]["hostname"]
    end
  end

  describe "organisation level image" do
    it "is given to other clients" do
      put "/v3/ltsp_servers/organisation-image-server",
        "load_avg" => "0.8",
        "cpu_count" => 2,
        "ltsp_image" => "organisationimage"
      create_device(
        :puavoHostname => "thinnoimage",
        :macAddress => "bc:5f:f4:56:59:72"
      )

      test_organisation = LdapOrganisation.first
      test_organisation.puavoDeviceImage = "organisationimage"
      test_organisation.save!

      post "/v3/sessions", "hostname" => "thinnoimage"
      assert_equal 200, last_response.status
      data = JSON.parse last_response.body
      assert_equal  "organisation-image-server", data["ltsp_server"]["hostname"]
    end
  end

  describe "no image at all" do
    it "gets the most idle server" do
      put "/v3/ltsp_servers/most-idle-server",
        "load_avg" => "0.0",
        "cpu_count" => 2,
        "ltsp_image" => "someimage"

      create_device(
        :puavoHostname => "thinnoimage",
        :macAddress => "bc:5f:f4:56:59:72"
      )

      post "/v3/sessions", "hostname" => "thinnoimage"
      assert_equal 200, last_response.status
      data = JSON.parse last_response.body
      assert_equal  "most-idle-server", data["ltsp_server"]["hostname"]
    end
  end

  describe "GET sessions" do
    before(:each) do
      put "/v3/ltsp_servers/most-idle-server",
        "load_avg" => "0.0",
        "cpu_count" => 2,
        "ltsp_image" => "someimage"

      create_device(
        :puavoHostname => "thinnoimage",
        :macAddress => "bc:5f:f4:56:59:72"
      )
    end

    it "can be fetched with GET" do
      post "/v3/sessions", "hostname" => "thinnoimage"
      assert_equal 200, last_response.status
      post_data = JSON.parse last_response.body
      assert post_data["uuid"], "has uuid"

      get "/v3/sessions/#{ post_data["uuid"] }"
      get_data = JSON.parse last_response.body
      assert_equal post_data["uuid"], get_data["uuid"]
    end

    it "all sessions can be fetched from index" do
      create_device(
        :puavoHostname => "thin1",
        :macAddress => "bc:5f:f4:56:59:72"
      )
      create_device(
        :puavoHostname => "thin2",
        :macAddress => "bc:5f:f4:56:59:73"
      )

      post "/v3/sessions", "hostname" => "thin1"
      assert_equal 200, last_response.status
      post "/v3/sessions", "hostname" => "thin2"
      assert_equal 200, last_response.status

      get "/v3/sessions"
      data = JSON.parse last_response.body

      assert_equal 2, data.size
      data.each do |s|
        assert s["ltsp_server"], "have ltsp server"
      end
    end

  end

end
