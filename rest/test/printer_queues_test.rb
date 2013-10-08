
require_relative "./helper"
class PrinterQueuesTest < MiniTest::Spec

def create_printer(server, name, attrs={})
  printer = Printer.new
  printer.attributes = {
    :printerDescription => name,
    :printerLocation => "school2",
    :printerMakeAndModel => "foo",
    :printerType => "1234",
    :printerURI => "socket://baz",
    :puavoPrinterPPD => "ppddata:#{ name }",
    :puavoServer => server.dn,
  }.merge(attrs)
  printer.save!
  printer
end


describe PuavoRest::PrinterQueues do
  before(:each) do
    Puavo::Test.clean_up_ldap
    FileUtils.rm_rf CONFIG["ltsp_server_data_dir"]

    @server1 = Server.new
    @server1.attributes = {
      :puavoHostname => "boot",
      :macAddress => "27:b0:59:3c:ac:a4",
      :puavoDeviceType => "bootserver"
    }
    @server1.save!

    @server2 = Server.new
    @server2.attributes = {
      :puavoHostname => "boot2",
      :macAddress => "00:60:2f:66:F8:5E",
      :puavoDeviceType => "bootserver"
    }
    @server2.save!

    @tmp_server = Server.new
    @tmp_server.attributes = {
      :puavoHostname => "tmpboot",
      :macAddress => "00:60:2f:E8:E3:6B",
      :puavoDeviceType => "bootserver"
    }
    @tmp_server.save!
    @broken_printer = create_printer(@tmp_server, "brokenprinter")
    @tmp_server.destroy

    @printer1 = create_printer(@server1, "printer1")
    @printer1 = create_printer(@server1, "printer1b")
    @printer2 = create_printer(@server2, "printer2")


    @school = School.create(
      :cn => "gryffindor",
      :displayName => "Gryffindor"
    )

  end

  describe "GET /v3/printer_queues" do
    before(:each) do
      basic_authorize "cucumber", "cucumber"
    end

    it "can get all printers" do
      get "/v3/printer_queues"
      assert_200
      @data = JSON.parse(last_response.body)
      assert_equal 4, @data.size
    end

    it "can filter printers by server" do
      get "/v3/printer_queues", "server_dn" => @server2.dn
      assert_200
      @data = JSON.parse(last_response.body)
      assert_equal 1, @data.size, "server2 has only one printer"
      printer = @data.first
      assert_equal "foo", printer["model"]
      assert_equal @server2.dn, printer["server_dn"]
      assert_equal "http://example.example.net/v3/printer_queues/printer2/ppd", @data.first["pdd_link"]
      assert_equal "boot2.example.example.net", @data.first["server_fqdn"]
      assert_equal "socket://baz", @data.first["local_uri"]
      assert_equal "ipp://boot2.example.example.net/printers/printer2", @data.first["remote_uri"]
    end

  end

  describe "GET http://example.example.net/v3/printer_queues/printer1/ppd" do
    it "returns ppd data" do
      basic_authorize "cucumber", "cucumber"
      get "http://example.example.net/v3/printer_queues/printer1/ppd"
      assert_200
      assert_equal "ppddata:printer1", last_response.body
    end

  end

end

end
