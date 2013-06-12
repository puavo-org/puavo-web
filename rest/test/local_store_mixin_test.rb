
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

end
