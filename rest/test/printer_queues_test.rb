
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
    :puavoServer => server.dn,
  }
  printer.save!
  printer
end


describe PuavoRest::PrinterQueues do
  before(:each) do
    Puavo::Test.clean_up_ldap
    FileUtils.rm_rf PuavoRest::CONFIG["ltsp_server_data_dir"]

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

end

end
