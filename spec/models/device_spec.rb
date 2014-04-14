require 'spec_helper'


describe Device do

  before(:each) do
    @school = School.create(
      :cn => "gryffindor",
      :displayName => "Gryffindor"
    )

    @device = Device.new
    @device.classes = ["top", "device", "puppetClient", "puavoNetbootDevice"]
    @device.puavoHostname = "fatclient-01"
    @device.macAddress = "33:2d:2b:13:ce:a0"
    @device.puavoDeviceType = "fatclient"
    @device.puavoSchool = @school.dn
    @device.save!


  end

  it "can save mountpoint " do
    @device.fs = ["nfs3"]
    @device.path = ["10.0.0.1/share"]
    @device.mountpoint = ["/home/share"]
    @device.options = []
    @device.save!

    assert_equal "nfs3", Device.first.fs[0]
    assert_equal "10.0.0.1/share", Device.first.path[0]
    assert_equal "/home/share", Device.first.mountpoint[0]
    assert_equal nil, Device.first.options[0]
  end

  it "can save mountpoint by json " do
    @device.puavoMountpoint = '{"fs":"nfs4", "path":"10.0.0.2/share", "mountpoint":"/home/public/share"}'
    @device.save!

    assert_equal "nfs4", Device.first.fs[0]
    assert_equal "10.0.0.2/share", Device.first.path[0]
    assert_equal "/home/public/share", Device.first.mountpoint[0]
    assert_equal nil, Device.first.options[0]
  end
end
