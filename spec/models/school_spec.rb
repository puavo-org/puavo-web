
require 'spec_helper'


describe School do

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

  before(:each) do
    @server = Server.new
    @server.attributes = {
      :puavoHostname => "boot",
      :macAddress => "27:b0:59:3c:ac:a4",
      :puavoDeviceType => "bootserver"
    }
    @server.save!

    @printer1 = create_printer @server, "printer1"
    @printer2 = create_printer @server, "printer2"

    @school = School.create(
      :cn => "gryffindor",
      :displayName => "Gryffindor"
    )
  end

  describe "printer management" do

    it "can add printer" do
      @school.add_printer @printer1
      assert_equal Array(@school.puavoPrinterQueue).first, @printer1.dn
    end

    it "can add two printers" do
      @school.add_printer @printer1
      @school.add_printer @printer2
      assert_equal Array(@school.puavoPrinterQueue), [@printer1.dn, @printer2.dn]
    end

    it "does not duplicate printers with add" do
      @school.add_printer @printer1
      @school.add_printer @printer1
      assert_equal Array(@school.puavoPrinterQueue), [@printer1.dn]
    end

    it "does case insensitive comparison" do
      @school.add_printer @printer1
      assert @school.has_printer?(@printer1.dn.to_s.upcase), "upcased dn must be ok"
    end

    it "can remove" do
      @school.add_printer @printer1
      @school.add_printer @printer2
      @school.remove_printer @printer2.dn
      assert_equal Array(@school.puavoPrinterQueue), [@printer1.dn]
    end

    it "remove does not crash if targer printer is missing" do
      @school.remove_printer @printer1.dn
    end


  end
end

