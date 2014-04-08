require_relative "./helper"

class PuavoRest::DeviceImages
class Test


describe PuavoRest::DeviceImages do
  def get_images(query="")
    get "/v3/device_images#{ query }", {}, {
      "HTTP_AUTHORIZATION" => "Bootserver"
    }
    assert_200
    JSON.parse(last_response.body)
  end

  before(:each) do
    Puavo::Test.clean_up_ldap
    PuavoRest::Session.local_store.flushdb
    FileUtils.rm_rf CONFIG["ltsp_server_data_dir"]

    @school1 = School.create(
      :cn => "school1",
      :displayName => "School 1"
    )

    @school2 = School.create(
      :cn => "school2",
      :displayName => "School 2"
    )


    @device1 = create_device(
      # :puavoDeviceImage => "ownimage",
      :puavoHostname => "fat1",
      :puavoDeviceType => "fatclient",
      :macAddress => "bf:9a:8c:1b:e0:6a",
      :puavoSchool => @school1.dn
    )

    @device2 = create_device(
      # :puavoDeviceImage => "ownimage",
      :puavoHostname => "fat2",
      :puavoDeviceType => "fatclient",
      :macAddress => "bf:9a:8c:1b:e0:6a",
      :puavoSchool => @school2.dn
    )

    @boot1 = Server.new
    @boot1.puavoDeviceType = "bootserver"
    @boot1.puavoHostname = "boot1"
    @boot1.macAddress = "00:60:2f:88:6E:81"
    @boot1.puavoSchool = @school1.dn
    @boot1.puavoDeviceImage = "bootdeviceimage1"
    @boot1.save!

    @boot2 = Server.new
    @boot2.puavoDeviceType = "bootserver"
    @boot2.puavoHostname = "boot2"
    @boot2.puavoSchool = @school2.dn
    @boot2.macAddress = "00:60:2f:02:F7:22"
    @boot2.puavoDeviceImage = "bootdeviceimage2"
    @boot2.save!


    test_organisation = LdapOrganisation.current
    test_organisation.puavoDeviceImage = "organisationimage"
    test_organisation.save!

    PuavoRest::Organisation.refresh
  end

  it "will find images set on organisation and boot server" do
    images = get_images
    assert_equal ["bootdeviceimage1", "bootdeviceimage2", "organisationimage"], images
  end

  it "will find images set on school" do
    @school1.puavoDeviceImage = "schoolimage"
    @school1.save!

    images = get_images
    assert_equal ["bootdeviceimage1", "bootdeviceimage2", "organisationimage", "schoolimage"], images
  end

  it "will find images set on devices" do
    @device1.puavoDeviceImage = "deviceimage"
    @device1.save!

    images = get_images
    assert_equal ["bootdeviceimage1", "bootdeviceimage2", "deviceimage", "organisationimage"], images
  end

  it "can filter schools by bootserver" do
    @school1.puavoDeviceImage = "schoolimage1"
    @school1.save!

    @school2.puavoDeviceImage = "schoolimage2"
    @school2.save!

    images = get_images("?boot_server=#{ @boot1.puavoHostname }")
    assert_equal ["bootdeviceimage1", "organisationimage", "schoolimage1"], images
  end

  it "can filter images by multiple bootservers" do
    @school1.puavoDeviceImage = "schoolimage1"
    @school1.save!

    @school2.puavoDeviceImage = "schoolimage2"
    @school2.save!

    School.create(
      :cn => "school3",
      :puavoDeviceImage => "schoolimage3",
      :displayName => "School 3"
    ).save!

    images = get_images("?boot_server[]=#{ @boot1.puavoHostname }&boot_server[]=#{ @boot2.puavoHostname }")
    assert_equal ["bootdeviceimage1", "bootdeviceimage2", "organisationimage", "schoolimage1", "schoolimage2"], images
  end

  it "can filter devices by bootserver" do
    @device1.puavoDeviceImage = "deviceimage1"
    @device1.save!

    @device2.puavoDeviceImage = "deviceimage2"
    @device2.save!

    images = get_images("?boot_server=#{ @boot1.puavoHostname }")
    assert_equal ["bootdeviceimage1", "deviceimage1", "organisationimage"], images
  end

end

end
end

