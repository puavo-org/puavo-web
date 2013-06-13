
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
  end

  it "has file metadata in index" do
    get "/v3/external_files"
    assert_200
    data = JSON.parse last_response.body
    assert_equal(
      [
        {"name"=>"test.txt", "data_hash"=>"f48dd853820860816c75d54d0f584dc863327a7c"},
        {"name"=>"another.txt", "data_hash"=>"7bd8e7cb8e1e8b7b2e94b472422512935c9d4519"}
      ],
    data
    )
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
    assert_equal(
      {"name"=>"test.txt", "data_hash"=>"f48dd853820860816c75d54d0f584dc863327a7c"},
      data
    )
  end

end
