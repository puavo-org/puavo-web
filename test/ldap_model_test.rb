require "./test/helper"

describe PuavoRest::Root do

  it "should respond hello on root" do
    get "/"
    assert_equal last_response.body, "hello"
  end

end
