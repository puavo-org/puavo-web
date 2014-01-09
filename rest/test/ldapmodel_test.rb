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

    class H < LdapModel
      ldap_map :a, :a
      ldap_map(:b, :b){ |v| self["a"] }
    end
    it "can reference other values from blocks using self" do

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

    class CustomMethod < LdapModel
      ldap_map :puavoValue, :value
      def value
        "foo"
      end
    end
    it "can use custom getter via method" do
      h = CustomMethod.new
      h.ldap_set("puavoValue", "bad")
      assert_equal h.value, "foo"
      assert_equal h["value"], "foo"

    end

    class FalseDefault < LdapModel
      ldap_map :puavoValue, :value, false
    end
    it "can set false as default value" do
      h = FalseDefault.new
      assert_equal false, h.value
    end

    class DefaultWithBlock < LdapModel
      ldap_map(:puavoValue, :value, false) do
        "bad"
      end
    end
    it "default values are not run through converters" do
      h = DefaultWithBlock.new
      assert_equal false, h.value
    end

    it "can create full links" do
      LdapModel.setup(:rest_root => "http://someroot") do
        h = LdapModel.new
        assert_equal "http://someroot/foo", h.link("/foo")
      end
    end

    describe "Computed attributes" do
      class ComputedAttributes < LdapModel
        ldap_map :puavoFoo, :foo
        computed_attr :bar
        def bar
          "bar#{ foo }bar"
        end
      end
      before do
        @model = ComputedAttributes.new.ldap_merge!(:puavoFoo => "foo")
      end

      it "can be accessed normally" do
        assert_equal "barfoobar", @model.bar
      end

      it "are added to to_hash" do
        h = @model.to_hash
        assert_equal "barfoobar", h["bar"]
      end

      it "are added to serialized json" do
        h = JSON.parse @model.to_json
        assert_equal "barfoobar", h["bar"]
      end

    end

    describe "skip serialize attributes" do
      class SkipSerializeAttributes < LdapModel
        ldap_map :puavoFoo, :foo
        ldap_map :puavoBar, :bar
        skip_serialize :bar
      end

      before do
        @model = SkipSerializeAttributes.new.ldap_merge!(
          :puavoFoo => "foo",
          :puavoBar => "bar"
        )
      end

      it "can be accessed normally" do
        assert_equal "bar", @model.bar
        assert_equal "foo", @model.foo
      end

      it "ignored attr is not present in to_hash serialization" do
        h = @model.to_hash
        assert_equal "foo", h["foo"]
        assert h["bar"].nil?, "bar was not missing!"
      end

      it "ignored attr is not present in to_json serialization" do
        h = JSON.parse @model.to_json
        assert_equal "foo", h["foo"]
        assert h["bar"].nil?, "bar was not missing!"
      end

    end

    describe "subclasses" do
      class Parent < LdapModel
        ldap_map :parentAttr, :parent_attr
      end

      class ChildA < Parent
        ldap_map :childAttrA, :child_attr_a
      end

      class ChildB < Parent
        ldap_map :childAttrB, :child_attr_b
      end

      it "can use own attributes when inherited" do
        child = ChildA.new
        child.ldap_set(:childAttrA, "bar")

        assert_equal "bar", child.child_attr_a
      end

      it "can use attributes from parent" do
        child = ChildA.new
        child.ldap_set(:parentAttr, "foo")

        assert_equal "foo", child.parent_attr
      end

      it "does not respond to other children methods" do
        child = ChildB.new
        assert !child.respond_to?(:child_attr_a)
        child.child_attr_b
      end

      it "to_hash serializes super class methods too" do
        child = ChildA.new
        child.ldap_set(:parentAttr, "foo")
        child.ldap_set(:childAttrA, "bar")

        h = child.to_hash
        assert_equal(
          {"parent_attr"=>"foo", "child_attr_a"=>"bar"},
          h
        )
      end

    end

  end



end
