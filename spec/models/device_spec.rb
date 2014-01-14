require 'spec_helper'


describe Device do

  before(:each) do
    @school = School.create(
      :cn => "gryffindor",
      :displayName => "Gryffindor"
    )


  end

  it "can save " do
    d = Device.new
    d.classes = ["top", "device", "puppetClient", "puavoNetbootDevice"]
    d.puavoHostname = "fatclient-01"
    d.macAddress = "33:2d:2b:13:ce:a0"
    d.puavoDeviceType = "fatclient"
    d.puavoSchool = @school.dn
    d.fs = ["nfs3"]
    d.save!

    assert_equal "nfs3", Device.first.fs[0]
  end
end
