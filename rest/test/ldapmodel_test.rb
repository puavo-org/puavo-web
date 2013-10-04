require_relative "./helper"
require_relative "../lib/ldapmodel"

describe LdapModel do

  describe "attribute mapping" do

    class TestHash1 < LdapModel
      ldap_map :fooBar, :foo_bar
      ldap_map :Baz, :baz
      ldap_map(:number, :integer) { |v| v.first.to_i }
      ldap_map :withDefault, :with_default, 2

      ldap_map :double, :double_one
      ldap_map :double, :double_two
    end

    class TestHash2 < LdapModel
      ldap_map :otherAttr, :other_attr
    end

    it "should convert attributes according ldap_map" do
      h = TestHash1.new
      h.ldap_set("fooBar", "value")
      assert_equal "value", h["foo_bar"]
      assert_equal "value", h.foo_bar
    end

    it "should ignore attributes without mapping" do
      h = TestHash1.new
      h.ldap_set("unknownattr", "value")
      assert h.empty?
    end

    it "can merge ldap attrs from hash" do
      h = TestHash1.new
      h.ldap_merge!("fooBar" => "value")
      assert_equal "value", h["foo_bar"]
      assert_equal "value", h.foo_bar
    end

    it "can use merge to create new value" do
      h = TestHash1.new
      h.ldap_set("fooBar", "value")
      new_h = h.merge("baz" => "value2")

      assert_equal "value", new_h.foo_bar
      assert_equal "value2", new_h.baz
    end


    it "can create new instances from normal hashes" do
      h = TestHash1.from_hash("fooBar" => "value")
      assert_equal "value", h["foo_bar"]
      assert_equal "value", h.foo_bar
    end

    it "mapping picks the first item if the value is array by default" do
      h = TestHash1.new
      h.ldap_set("fooBar",  ["first", "second"])
      assert_equal "first", h["foo_bar"]
      assert_equal "first", h.foo_bar
    end

    it "mapping can have custom converter as block" do
      h = TestHash1.new
      h.ldap_set("number",  "2")
      assert_equal 2, h["integer"]
      assert_equal 2, h.integer
    end

    it "can use defaults from mapping" do
      h = TestHash1.new
      h.ldap_set("withDefault", nil)
      assert_equal 2, h["with_default"]
      assert_equal 2, h.with_default
    end

    it "considers false as value" do
      h = TestHash1.new
      h.ldap_set("withDefault", false)
      assert_equal false, h["with_default"]
      assert_equal false, h.with_default
    end

    it "can reference other values from blocks using self" do
      class H < LdapModel
        ldap_map :a, :a
        ldap_map(:b, :b){ |v| self["a"] }
      end

      h = H.new
      h.ldap_set("a", "foo")
      h.ldap_set("b", "bar")

      assert_equal "foo", h["b"]
      assert_equal "foo", h.b
    end

    it "can have multiple mappings for single value" do
      h = TestHash1.new
      h.ldap_set("double", "double_value")
      assert_equal "double_value", h["double_one"]
      assert_equal "double_value", h["double_two"]
      assert_equal "double_value", h.double_two
    end

    # it "can serialize to json" do
    #   h = TestHash1.new
    #   h.ldap_set("double", "double_value")
    #   assert_equal "nil", h.to_json
    # end

    it "can use custom getter via method" do
      class CustomMethod < LdapModel
        ldap_map :puavoValue, :value
        def value
          "foo"
        end
      end

      h = CustomMethod.new
      h.ldap_set("puavoValue", "bad")
      assert_equal h.value, "foo"
      assert_equal h["value"], "foo"

    end

    it "can set false as default value" do
      class FalseDefault < LdapModel
        ldap_map :puavoValue, :value, false
      end

      h = FalseDefault.new
      assert_equal false, h.value
    end

    it "default values are not run through converters" do
      class DefaultWithBlock < LdapModel
        ldap_map(:puavoValue, :value, false) do
          "bad"
        end
      end

      h = DefaultWithBlock.new
      assert_equal false, h.value
    end

    it "can create full links" do

      LdapModel.setup(:rest_root => "http://someroot") do
        h = LdapModel.new
        assert_equal "http://someroot/foo", h.link("/foo")
      end

    end
  end


end
