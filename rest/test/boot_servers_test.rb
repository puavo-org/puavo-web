require_relative "./helper"

describe PuavoRest::BootServer do

  before(:each) do
    Puavo::Test.clean_up_ldap
    @school = School.create(
      :cn => "gryffindor",
      :displayName => "Gryffindor",
      :puavoDeviceImage => "schoolprefimage",
      :puavoPersonalDevice => true,
      :puavoAllowGuest => true
    )

    @school2 = School.create(
      :cn => "exampleschool1",
      :displayName => "Example school 1"
    )
    @server1 = Server.new
    @server1.attributes = {
      :puavoHostname => "server1",
      :macAddress => "bc:5f:f4:56:59:71",
      :puavoSchool => @school.dn,
      :puavoTag => ["servertag"],
      :puavoDeviceType => "bootserver"
    }
    @server1.save!

    @ltsp_server = Server.new
    @ltsp_server.attributes = {
      :puavoHostname => "evil-ltsp-server",
      :macAddress => "00:60:2f:56:07:5D",
      :puavoSchool => @school.dn,
      :puavoDeviceType => "ltspserver"
    }
    @ltsp_server.save!

    @printer = Printer.create(
      :printerDescription => "printer1",
      :printerLocation => "school2",
      :printerMakeAndModel => "foo",
      :printerType => "1234",
      :printerURI => "socket://baz",
      :puavoServer => @server1.dn )

    @school.add_wireless_printer(@printer)
    @school2.add_wireless_printer(@printer)

  end

  describe "basic get resources" do

    it "lists all servers from GET /v3/boot_servers" do
      get "/v3/boot_servers", {}, {
        "HTTP_AUTHORIZATION" => "Bootserver"
      }
      assert_200
      data = JSON.parse last_response.body
      assert_equal 1, data.size
      assert_equal "server1", data.first["hostname"]
      assert data.first["dn"]
      assert data.first["school_dns"]
    end

    it "can list single boot server" do
      get "/v3/boot_servers/server1", {}, {
        "HTTP_AUTHORIZATION" => "Bootserver"
      }
      assert_200
      data = JSON.parse last_response.body
      assert_equal("server1", data["hostname"])
      assert_equal(Array, data["school_dns"].class, "has array of schools")
      assert_equal(Array, data["tags"].class, "has a tags array")
      assert(
        data["tags"].include?("servertag"),
        "Has 'servertag' in #{ data["tags"].inspect }"
      )
    end

    it "can be used to fetch single boot server data by hostname" do
      get "/v3/boot_servers/server1", {}, {
        "HTTP_AUTHORIZATION" => "Bootserver"
      }
      assert_200
      data = JSON.parse last_response.body
      assert_equal "server1", data["hostname"]
      assert data["dn"]
      assert data["school_dns"]
    end

    it "must not make ltsp server available as boot server" do
      get "/v3/boot_servers/evil-ltsp-server", {}, {
        "HTTP_AUTHORIZATION" => "Bootserver"
      }
      assert_equal 404, last_response.status
      data = JSON.parse last_response.body
      assert data["error"]
      assert_equal("NotFound", data["error"]["code"])
    end

  end

  describe "wireless printer queues by boot server" do
    before(:each) do
      get "/v3/boot_servers/server1/wireless_printer_queues", {}, {
        "HTTP_AUTHORIZATION" => "Bootserver"
      }
      assert_200
      @data = JSON.parse last_response.body
    end

    it "has one printer queue" do
      assert_equal 1, @data.count
    end

    describe "first printer queues information" do

      before(:each) do
        @printer = @data.first
      end

      it "has server fqdn" do
        assert_equal "server1.www.example.net", @printer["server_fqdn"]
      end

      it "has name" do
        assert_equal "printer1", @printer["name"]
      end

      it "has description" do
        assert_equal "printer1", @printer["description"]
      end

      it "has remote_uri" do
        assert_equal "ipp://server1.www.example.net/printers/printer1", @printer["remote_uri"]
      end
    end
  end

end
