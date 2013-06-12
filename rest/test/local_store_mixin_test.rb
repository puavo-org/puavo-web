
require_relative "./helper"
require_relative "../ldap_hash"
require_relative "../local_store_mixin"


describe LocalStoreMixin do

  before(:each) do
    FileUtils.rm_rf PuavoRest::CONFIG["ltsp_server_data_dir"]
    LdapHash.setup(
      :organisation => {
        "domain" => "testdomain"
      }
    )
  end

  it "can persist LdapHashes" do
    class PersistentableLdapHash < LdapHash
      include LocalStoreMixin
    end

    h = PersistentableLdapHash.new
    h["foo"] = "bar"
    h.save "test_hash"

    loaded = PersistentableLdapHash.load("test_hash")
    assert_equal "bar", loaded["foo"]
  end

  it "can load all saved objects" do
    class PersistentableLdapHash < LdapHash
      include LocalStoreMixin
    end

    h = PersistentableLdapHash.new
    h["foo"] = "bar"
    h.save "test_hash"

    h = PersistentableLdapHash.new
    h["baz"] = "fuz"
    h.save "another_hash"

    assert_equal 2, PersistentableLdapHash.all.size

  end

  describe "seperate classes" do
    before(:each) do
      class A < LdapHash
        include LocalStoreMixin
      end
      class B < LdapHash
        include LocalStoreMixin
      end

      @a = A.new
      @a["name"] = "a class"
      @b = B.new
      @b["name"] = "b class"

      @a.save "test"
      @b.save "test"
    end

    it "won't mixup classes with the same key" do
      assert_equal "a class", A.load("test")["name"]
      assert_equal "b class", B.load("test")["name"]
    end

    it "won't mixup classes in all method" do
      assert_equal 1, A.all.size
      assert_equal 1, B.all.size
    end

  end
end
