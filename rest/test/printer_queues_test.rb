
require_relative "./helper"

describe PuavoRest::PrinterQueues do
  before(:each) do
    Puavo::Test.clean_up_ldap
    FileUtils.rm_rf PuavoRest::CONFIG["ltsp_server_data_dir"]

    @server = create_server(
      :puavoHostname => "testbootserver",
      :macAddress => "bc:5f:f4:56:59:f4",
      :userPassword => "secret"
    )

    @printer = Printer.create(
      :printerMakeAndModel => "model1",
      :printerDescription => "Tulostin-Samsung",
      :printerLocation => "Tuotanto",
      :printerType => "8400924",
      :printerURI => "socket://tulostin-toimisto-samsung-550",

      :puavoServer => @server.dn
    )
    @printer.save!

    @printer2 = Printer.create(
      :printerMakeAndModel => "model2",
      :printerDescription => "Just some other printer",
      :printerLocation => "Tuotanto",
      :printerType => "8400924",
      :printerURI => "socket://otherprinter",

      :puavoServer => "puavoId=9999999999,ou=Servers,ou=Hosts,dc=edu,dc=example,dc=fi"
    )
    @printer2.save!

  end

  it "can list printer queues" do
    basic_authorize @server.dn, "secret"
    get "/v3/printer_queues"
    assert_200
    res = JSON.parse(last_response.body)
    assert_equal 2, res.size
    assert_equal ["model1", "model2"], (res.map do |p|
      p["model"]
    end)
  end

  it "can filter printer queues list by server" do
    basic_authorize @server.dn, "secret"
    get "/v3/printer_queues?server=#{ @server.dn }"
    assert_200
    res = JSON.parse(last_response.body)
    assert_equal 1, res.size
    assert_equal ["model1"], (res.map do |p|
      p["model"]
    end)
  end


end
