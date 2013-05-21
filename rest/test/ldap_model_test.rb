require_relative "./helper"

describe PuavoRest::LdapModel do

  class CustomModel < PuavoRest::LdapModel
    ldap_attr_conversion :cn, :name
    ldap_attr_conversion(:foo, :bar) { |v| v.to_i }
  end

  it "can convert atribute names" do
    json = CustomModel.convert({
      "cn" => ["foo"]
    })
    assert_equal "foo", json["name"]
  end


  it "can use custom value conversion blocks" do
    json = CustomModel.convert({
      "foo" => "2"
    })
    assert_equal 2, json["bar"]
  end

end


