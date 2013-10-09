
require_relative "./helper"
require_relative "../lib/ldapmodel"

describe LdapModel do

  class ClassStoreA < LdapModel
    pretty2ldap[:foo] = 1
    computed_attr :bar
    def bar
      "a bar"
    end
    def foo
      "a foo"
    end
  end
  class ClassStoreB < LdapModel
    pretty2ldap[:foo] = 2
    def bar
      "b bar"
    end

    def foo
      "b foo"
    end
  end

  describe "class store" do

    it "can be accessed from class" do
      assert_equal 1, ClassStoreA.pretty2ldap[:foo]
    end

    it "can be accessed from instance" do
      o = ClassStoreA.new
      assert_equal 1, o.pretty2ldap[:foo]
    end

    it "does not conflict with other classes" do
      assert_equal 2, ClassStoreB.pretty2ldap[:foo]
    end

    it "does not conflict with other classes in instance level" do
      o = ClassStoreB.new
      assert_equal 2, o.pretty2ldap[:foo]
    end

    it "computed attributes are not shared with different classes" do
      a = ClassStoreA.new
      assert_equal "a bar", a.to_hash["bar"]

      b = ClassStoreB.new
      assert b.to_hash["bar"].nil?, "was not nil: #{ b["bar"] }"
    end

  end

end
