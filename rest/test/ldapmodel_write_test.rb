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
        $events.push(:saved)
      end
      def add(dn, mods)
        $events.push(:added)
      end
    end


    it "before update is called before saving changes to existing model" do
      class BeforeTestModel < LdapModel
        ldap_map :dn, :dn, :default => "fakedn"
        ldap_map :fooBar, :bar
        before :update do
          $events.push(:hook_called)
        end
      end

      LdapModel.stub(:connection, MockConnection.new) do
        m = BeforeTestModel.new({:bar => "val"}, {:existing => true})
        m.save!
      end

      assert_equal [:hook_called, :saved], $events
    end

    it "before create is called when new model is created" do
      class BeforeCreateTestModel < LdapModel
        ldap_map :dn, :dn
        ldap_map :fooBar, :bar
        before :create do
          $events.push(:create_hook_called)
        end
      end

      LdapModel.stub(:connection, MockConnection.new) do
        m = BeforeCreateTestModel.new({:bar => "val"})
        m.save!
      end

      assert_equal [:create_hook_called, :added], $events
    end

    it "after update is called after saving" do
      class AfterTestModel < LdapModel
        ldap_map :dn, :dn, :default => "fakedn"
        ldap_map :fooBar, :bar
        after :update do
          $events.push(:hook_called)
        end
      end

      LdapModel.stub(:connection, MockConnection.new) do
        m = AfterTestModel.new({:bar => "val"}, {:existing => true})
        m.save!
      end

      assert_equal [:saved, :hook_called], $events
    end

    it "context is the instance" do

      class ContextTestModel < LdapModel
        ldap_map :dn, :dn, :default => "fakedn"
        ldap_map :fooBar, :bar
        ldap_map :fooBaz, :baz

        before :update do
          $events.push(bar)
          self.baz = "hook can modify"
        end

      end

      m = ContextTestModel.new({:bar => "val"}, {:existing => true})
      LdapModel.stub(:connection, MockConnection.new) do
        m.save!
      end

      assert_equal ["val", :saved], $events
      assert_equal "hook can modify", m.baz

    end

    it "(s) are executed in the order they are defined" do

      class MultipleHooks < LdapModel
        ldap_map :dn, :dn, :default => "fakedn"
        ldap_map :fooBar, :bar
        before :update do
          $events.push(:first_hook_called)
        end
        before :update do
          $events.push(:second_hook_called)
        end
      end

      m = MultipleHooks.new({:bar => "val"}, {:existing => true})
      LdapModel.stub(:connection, MockConnection.new) do
        m.save!
      end
      assert_equal [:first_hook_called, :second_hook_called, :saved], $events

    end

    it "can be defined for :create and :update at once" do

      class GenericHook < LdapModel
        ldap_map :dn, :dn, :default => "fakedn"
        ldap_map :fooBar, :bar
        before :create, :update do
          $events.push(:generic_hook_called)
        end
      end

      m = GenericHook.new({:bar => "val"})
      LdapModel.stub(:connection, MockConnection.new) do
        m.save! # create
        m.bar = "lol"
        m.save! # update
      end
      assert_equal [:generic_hook_called, :added, :generic_hook_called, :saved], $events

    end

  end


end
