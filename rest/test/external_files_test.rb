
require_relative "./helper"

describe PuavoRest::ExternalFiles do

  before(:each) do
    Puavo::Test.clean_up_ldap
    @file1 = ExternalFile.new
    @file1.cn = "test.txt"
    @file1.puavoData = "test data"
    @file1.save!

    @file2 = ExternalFile.new
    @file2.cn = "another.txt"
    @file2.puavoData = "some other data"
    @file2.save!

    @school = School.create(
      :cn => "gryffindor",
      :displayName => "Gryffindor"
    )

    @device = create_device(
      :puavoHostname => "athin01",
      :macAddress => "bf:9a:8c:1b:e0:6a",
      :puavoSchool => @school.dn,
      :puavoPrinterPPD => 'PPD-data'
    )

    @device = create_device(
      :puavoHostname => "athin02",
      :macAddress => "bf:9a:8c:1b:e0:6b",
      :puavoSchool => @school.dn
    )

  end

  it "has file metadata in index" do
    get "/v3/external_files"
    assert_200
    data = JSON.parse last_response.body

    assert_equal "test.txt", data[0]["name"]
    assert_equal "f48dd853820860816c75d54d0f584dc863327a7c", data[0]["data_hash"]

    assert_equal "another.txt", data[1]["name"]
    assert_equal "7bd8e7cb8e1e8b7b2e94b472422512935c9d4519", data[1]["data_hash"]
  end

  it "has file contents" do
    get "/v3/external_files/test.txt"
    assert_200
    assert_equal "test data", last_response.body
  end

  it "has file metadata" do
    get "/v3/external_files/test.txt/metadata"
    assert_200
    data = JSON.parse last_response.body

    assert_equal "test.txt", data["name"]
    assert_equal "f48dd853820860816c75d54d0f584dc863327a7c", data["data_hash"]
  end

  it "has file metadata in index by device" do
    get "/v3/devices/athin01/external_files"
    assert_200
    data = JSON.parse last_response.body

    assert_equal "test.txt", data[0]["name"]
    assert_equal "f48dd853820860816c75d54d0f584dc863327a7c", data[0]["data_hash"]

    assert_equal "another.txt", data[1]["name"]
    assert_equal "7bd8e7cb8e1e8b7b2e94b472422512935c9d4519", data[1]["data_hash"]

    assert_equal "printer.ppd", data[2]["name"]
    assert_equal "f6faa9d255137ce1482dc9a958f7299c234ef4f9", data[2]["data_hash"]

  end

  it "has no file metadata of printer_ppd in index by device" do
    get "/v3/devices/athin02/external_files"
    assert_200
    data = JSON.parse last_response.body

    assert_equal "test.txt", data[0]["name"]
    assert_equal "f48dd853820860816c75d54d0f584dc863327a7c", data[0]["data_hash"]

    assert_equal "another.txt", data[1]["name"]
    assert_equal "7bd8e7cb8e1e8b7b2e94b472422512935c9d4519", data[1]["data_hash"]
  end

  it "has printer.ppd file contents by hostname" do
    get "/v3/devices/athin01/external_files/printer.ppd"
    assert_200
    assert_equal "PPD-data", last_response.body
  end

  it "has file contents by hostname" do
    get "/v3/devices/athin01/external_files/test.txt"
    assert_200
    assert_equal "test data", last_response.body
  end

end
