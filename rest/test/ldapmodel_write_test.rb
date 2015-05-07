require_relative "./helper"
require_relative "../lib/ldapmodel"

describe LdapModel do

  describe "attribute writing" do

    class WriteableLM < LdapModel
      ldap_map :fooBar, :foo_bar

      ldap_map :jsonValue, :json_value

      def json_value
        JSON.parse(get_own(:json_value)) if get_own(:json_value)
      end

      def json_value=(value)
        write_raw(:jsonValue, [value.to_json])
      end

    end

    it "should convert attributes according ldap_map" do
      h = WriteableLM.from_ldap_hash({
        "fooBar" => "bar"
      })

      assert_equal "bar", h.foo_bar
      h.foo_bar = "foo"
      assert_equal "foo", h.foo_bar

    end

    it "can use custom getters and setters" do
      h = WriteableLM.from_ldap_hash({
        "jsonValue" => '{"lol": "haha"}'
      })

      assert_equal "haha", h.json_value["lol"]

      h.json_value = {"lol" => "buhaha"}
      assert_equal "buhaha", h.json_value["lol"]

    end

    class WriteableBulk < LdapModel
      ldap_map :fooBar, :bar
      ldap_map :fooBaz, :baz
    end

    it "can update attributes in bulk using Model#update" do
      h = WriteableBulk.from_ldap_hash({
        "fooBar" => "a",
        "fooBaz" => "b",
      })

      h.update!({
        "bar" => "c",
        "baz" => "d",
      })

      assert_equal "c", h.bar
      assert_equal "d", h.baz

    end

  end

  describe "Hook" do

    before do
      $events = []
    end

    after do
      $events = nil
    end

    class MockConnection
      def modify(dn, mods)
        puts "#"*80
        puts "running save"
        puts "#"*80
        $events.push(:saved)
      end
    end


    it "before save is called before saving" do
      class BeforeTestModel < LdapModel
        ldap_map :dn, :dn, :default => "fakedn"
        ldap_map :fooBar, :bar
        before :save do
          $events.push(:hook_called)
        end
      end

      LdapModel.stub(:connection, MockConnection.new) do
        m = BeforeTestModel.new :bar => "val"
        m.save!
      end

      assert_equal [:hook_called, :saved], $events
    end

    it "after save is called after saving" do
      class AfterTestModel < LdapModel
        ldap_map :dn, :dn, :default => "fakedn"
        ldap_map :fooBar, :bar
        after :save do
          $events.push(:hook_called)
        end
      end

      LdapModel.stub(:connection, MockConnection.new) do
        m = AfterTestModel.new :bar => "val"
        m.save!
      end

      assert_equal [:saved, :hook_called], $events
    end

    it "context is the instance" do

      class ContextTestModel < LdapModel
        ldap_map :dn, :dn, :default => "fakedn"
        ldap_map :fooBar, :bar
        ldap_map :fooBaz, :baz

        before :save do
          $events.push(bar)
          self.baz = "hook can modify"
        end

      end

      m = ContextTestModel.new :bar => "val"
      LdapModel.stub(:connection, MockConnection.new) do
        m.save!
      end

      assert_equal ["val", :saved], $events
      assert_equal "hook can modify", m.baz

    end

  end
end
