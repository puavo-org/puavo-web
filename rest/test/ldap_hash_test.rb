require_relative "./helper"
require_relative "../ldap_hash"

LdapHash = PuavoRest::LdapHash

describe LdapHash do

  describe "attribute mapping" do

    class TestHash1 < LdapHash
      ldap_map :fooBar, :foo_bar
      ldap_map(:number, :integer) { |v| v.first.to_i }
      ldap_map :withDefault, :with_default, 2
    end

    class TestHash2 < LdapHash
      ldap_map :otherAttr, :other_attr
    end

    it "should convert attributes according ldap_map" do
      h = TestHash1.new
      h.ldap_set("fooBar", "value")
      assert_equal "value", h["foo_bar"]
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
    end

    it "can use normat attr set" do
      h = TestHash1.new
      h["hello"] = "value"
      assert_equal "value", h["hello"]
    end

    it "can create new instances from normal hashes" do
      h = TestHash1.from_hash("fooBar" => "value")
      assert_equal "value", h["foo_bar"]
    end

    it "mapping picks the first item if the value is array by default" do
      h = TestHash1.new
      h.ldap_set("fooBar",  ["first", "second"])
      assert_equal "first", h["foo_bar"]
    end

    it "mapping can have custom converter as block" do
      h = TestHash1.new
      h.ldap_set("number",  "2")
      assert_equal 2, h["integer"]
    end

    it "can use defaults from mapping" do
      h = TestHash1.new
      h.ldap_set("withDefault", nil)
      assert_equal 2, h["with_default"]
    end

    it "considers false as value" do
      h = TestHash1.new
      h.ldap_set("withDefault", false)
      assert_equal false, h["with_default"]
    end

    it "can reference other values from blocks using self" do
      class H < LdapHash
        ldap_map :a, :a
        ldap_map(:b, :b){ |v| self["a"] }
      end

      h = H.new
      h.ldap_set("a", "foo")
      h.ldap_set("b", "bar")

      assert_equal "foo", h["b"]
    end

    it "can create full links" do

      LdapHash.setup(:rest_root => "http://someroot") do
        h = LdapHash.new
        assert_equal "http://someroot/foo", h.link("/foo")
      end

    end
  end


end
