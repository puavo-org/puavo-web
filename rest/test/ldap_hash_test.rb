require_relative "./helper"
require_relative "../ldap_hash"


describe LdapHash do

  describe "attribute mapping" do

    class TestHash1 < LdapHash
      ldap_map :fooBar, :foo_bar
    end

    class TestHash2 < LdapHash
      ldap_map :otherAttr, :other_attr
    end

    it "should convert attributes according ldap_map" do
      h = TestHash1.new
      h.ldap_set("fooBar", "value")
      assert_equal "value", h["foo_bar"]
    end

    it "don't mix ldap maps with other classes" do
      h = TestHash1.new
      assert_raises LdapHash::UnknownLdapMap do
        h.ldap_set("otherAttr", "value")
      end
    end

    it "can merge ldap attrs from hash" do
      h = TestHash1.new
      h.ldap_merge!(:fooBar => "value")
      assert_equal "value", h["foo_bar"]
    end

    it "can use normat attr set" do
      h = TestHash1.new
      h["hello"] = "value"
      assert_equal "value", h["hello"]
    end

    it "can create new instances from normal hashes" do
      h = TestHash1.from_hash(:fooBar => "value")
      debugger; nil
      assert_equal "value", h["foo_bar"]
    end

  end

  describe "connection management" do
    before(:each) do
      LdapHash.setup(
        :connection => "connection object",
        :organisation => "organisation object"
      )
    end

    it "can access connection and organisation from class" do
      assert_equal "connection object", LdapHash.connection
      assert_equal "organisation object", LdapHash.organisation
    end

    it "connection can be changed temporally with block" do
      called = false
      LdapHash.with(:connection => "tmp conn") do
        assert_equal "tmp conn", LdapHash.connection
        assert_equal(
          "organisation object",
          LdapHash.organisation,
          "organisation is not changed"
        )
        called = true
      end
      assert_equal "connection object", LdapHash.connection
      assert called
    end

    it "connection is changed to subclasses too" do
      called = false
      class Subclass < LdapHash; end

      LdapHash.with(:connection => "subclass conn") do
        called = true
        assert_equal "subclass conn", Subclass.connection
      end

      assert called
    end

  end


end
