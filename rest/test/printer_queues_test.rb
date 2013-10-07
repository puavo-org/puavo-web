
require_relative "./helper"
class PrinterQueuesTest < MiniTest::Spec

def create_printer(server, name)
  printer = Printer.new
  printer.attributes = {
    :printerDescription => name,
    :printerLocation => "school2",
    :printerMakeAndModel => "foo",
    :printerType => "1234",
    :printerURI => "socket://baz",
    :puavoPrinterPPD => "ppddata:#{ name }",
    :puavoServer => server.dn,
  }
  printer.save!
  printer
end


describe PuavoRest::PrinterQueues do
  before(:each) do
    Puavo::Test.clean_up_ldap
    FileUtils.rm_rf CONFIG["ltsp_server_data_dir"]

    @server = Server.new
    @server.attributes = {
      :puavoHostname => "boot",
      :macAddress => "27:b0:59:3c:ac:a4",
      :puavoDeviceType => "bootserver"
    }
    @server.save!

    @printer1 = create_printer(@server, "printer1")
    @printer2 = create_printer(@server, "printer2")

    @school = School.create(
      :cn => "gryffindor",
      :displayName => "Gryffindor"
    )

  end

  describe "GET /v3/printer_queues" do
    before do
      basic_authorize "cucumber", "cucumber"
      get "/v3/printer_queues"
      assert_200
      @data = JSON.parse(last_response.body)
      assert_equal 2, @data.size, "has two priters"
    end

    it "first has name" do
      assert_equal "printer1", @data.first["name"]
    end

    it "first has pdd_link" do
      assert_equal "http://example.example.net/v3/printer_queues/printer1/ppd", @data.first["pdd_link"]
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
