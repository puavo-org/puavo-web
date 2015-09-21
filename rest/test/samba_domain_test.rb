
require_relative "./helper"
describe PuavoRest::SambaDomain do

  before(:each) do
    Puavo::Test.clean_up_ldap
  end


  it "can get get new samba rids" do
    basic_authorize "cucumber", "cucumber"

    post "/v3/samba_generate_next_rid"
    assert_200
    data = JSON.parse(last_response.body)
    first_rid = data["next_rid"]

    post "/v3/samba_generate_next_rid"
    assert_200
    data = JSON.parse(last_response.body)
    second_rid = data["next_rid"]

    assert_equal first_rid+1, second_rid
  end

  it "is specific to organisations" do
    basic_authorize "cucumber", "cucumber"

    get "/v3/samba_current_rid"
    assert_200
    data = JSON.parse(last_response.body)
    current_rid = data["current_rid"]

    basic_authorize "uid=admin,o=puavo", "password"
    post "/v3/samba_generate_next_rid", {}, {
      "HTTP_HOST" => "anotherorg.opinsys.net"
    }
    assert_200

    basic_authorize "cucumber", "cucumber"
    get "/v3/samba_current_rid"
    assert_200
    data = JSON.parse(last_response.body)
    assert_equal current_rid, data["current_rid"]

  end

end
