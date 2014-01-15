
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
      :displayName => "Gryffindor",
      :puavoPersonalDevice => true
    )
  end

  it "can save mountpoint " do
    @school.fs = ["nfs3"]
    @school.path = ["10.0.0.1/share"]
    @school.mountpoint = ["/home/share"]
    @school.options = []
    @school.save!

    reloaded_school = School.find(@school.id)
    assert_equal "nfs3", reloaded_school.fs[0]
    assert_equal "10.0.0.1/share", reloaded_school.path[0]
    assert_equal "/home/share", reloaded_school.mountpoint[0]
    assert_equal nil, reloaded_school.options[0]

  end

  it "do not save empty  mountpoint " do
    @school.fs = [""]
    @school.path = [""]
    @school.mountpoint = [""]
    @school.options = [""]
    @school.save!

    reloaded_school = School.find(@school.id)
    assert_equal nil, reloaded_school.puavoMountpoint

  end

  describe "printer management" do

    it "can add printer" do
      @school.add_printer @printer1

      @school = @school.find_self
      assert_equal Array(@school.puavoPrinterQueue).first, @printer1.dn
    end

    it "adding a printer does not break other attributes" do
      @school.add_printer @printer1
      assert_equal Array(@school.puavoPersonalDevice).first, true
    end

    it "adding a wireless printer does not break other attributes" do
      @school.add_wireless_printer @printer1
      assert_equal Array(@school.puavoPersonalDevice).first, true
    end

    it "can add two printers" do
      @school.add_printer @printer1
      @school.add_printer @printer2

      @school = @school.find_self
      assert_equal Array(@school.puavoPrinterQueue), [@printer1.dn, @printer2.dn]
    end

    it "does not duplicate printers with add" do
      @school.add_printer @printer1
      @school.add_printer @printer1

      @school = @school.find_self
      assert_equal Array(@school.puavoPrinterQueue), [@printer1.dn]
    end

    it "does case insensitive comparison" do
      @school.add_printer @printer1

      @school = @school.find_self
      assert @school.has_printer?(@printer1.dn.to_s.upcase), "upcased dn must be ok"
    end

    it "can remove" do
      @school.add_printer @printer1
      @school.add_printer @printer2
      @school.remove_printer @printer2.dn

      @school = @school.find_self
      assert_equal Array(@school.puavoPrinterQueue), [@printer1.dn]
    end

    it "remove does not crash if targer printer is missing" do
      @school.remove_printer @printer1.dn
    end


  end
end

