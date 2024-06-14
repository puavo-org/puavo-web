require_relative "./helper"

require 'set'

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
      :puavoImageSeriesSourceURL => [
        "https://foobar.puavo.net/images1.json",
        "https://foobar.puavo.net/images2.json"],
      :puavoDeviceType => "bootserver",
      :puavoConf => '{ "puavo.kernel.version": "fresh" }',
      :puavoNotes => 'This is an example bootserver'
    }
    @server1.save!

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
      assert_equal 'This is an example bootserver', data.first['notes']
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
      assert_equal( Set.new(["https://foobar.puavo.net/images1.json",
                             "https://foobar.puavo.net/images2.json"]),
                    Set.new(data["image_series_source_urls"]) )

      assert_equal 'This is an example bootserver', data['notes']
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
      assert_equal 'This is an example bootserver', data['notes']
    end
  end

  describe "POST /v3/boot_servers/:hostname" do
    it "can write preferred_image POST" do
      # XXX Use server's own dn
      basic_authorize "cucumber", "cucumber"
      post "/v3/boot_servers/server1", { "preferred_image" => "foo" }
      assert_200

      get "/v3/boot_servers/server1", {}, {
        "HTTP_AUTHORIZATION" => "Bootserver"
      }
      assert_200
      data = JSON.parse(last_response.body)
      assert_equal "foo", data["preferred_image"]

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
        assert_equal "server1.example.puavo.net", @printer["server_fqdn"]
      end

      it "has name" do
        assert_equal "printer1", @printer["name"]
      end

      it "has description" do
        assert_equal "printer1", @printer["description"]
      end

      it "has remote_uri" do
        assert_equal "ipp://server1.example.puavo.net/printers/printer1", @printer["remote_uri"]
      end
    end
  end


  describe "basic get resources with organisation fallback" do
    before(:each) do
      test_organisation = LdapOrganisation.first # TODO: fetch by name
      test_organisation.puavoImageSeriesSourceURL = "https://foobar.puavo.net/organisationprefimages1.json"
      test_organisation.puavoConf = '{ "puavo.time.timezone": "Europe/Rome" }'
      test_organisation.save!

      @server1.puavoImageSeriesSourceURL = nil
      @server1.save

    end

    it "can see organisations image series source urls" do
      get "/v3/boot_servers/server1", {}, {
        "HTTP_AUTHORIZATION" => "Bootserver"
      }
      assert_200
      data = JSON.parse last_response.body
      assert_equal( Set.new(["https://foobar.puavo.net/organisationprefimages1.json"]),
                    Set.new(data["image_series_source_urls"]) )
    end

    it "puavo-conf values are passed" do
      get "/v3/boot_servers/server1", {}, {
        "HTTP_AUTHORIZATION" => "Bootserver"
      }
      assert_200

      data = JSON.parse last_response.body
      conf = data['puavoconf']

      assert conf.kind_of?(Hash),
	     'bootserver data has "puavoconf" that is a Hash'
      assert_equal 'fresh', conf['puavo.kernel.version']
      assert_equal 'Europe/Rome', conf['puavo.time.timezone']
    end
  end

  describe 'device certificate' do
    before(:each) do
      @key = OpenSSL::PKey::RSA.new(2048)
      @csr = OpenSSL::X509::Request.new
      @csr.version = 0
      @csr.public_key = @key.public_key

      @csr.sign(@key, OpenSSL::Digest::SHA256.new)
    end

    it 'sign new certificate' do
      basic_authorize @server1.dn.to_s, @server1.ldap_password
      post( '/v3/hosts/certs/sign',
            { 'hostname'            => 'server1',
              'certificate_request' => @csr.to_pem } )
      assert_200
      @data = JSON.parse last_response.body

      assert @data.keys.include?('certificate')
      assert @data.keys.include?('org_ca_certificate_bundle')
      assert @data.keys.include?('root_ca_certificate')
    end
  end
end
