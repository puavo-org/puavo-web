class LdapModel
  # Store for ldap attribute mappings
  @@_class_store = {}
  def self._class_store
    @@_class_store[self] ||= {}
  end

  # Like double at sign attributes (@@foo) but they are not shared between
  # subclasses
  #
  # class Foo
  #   class_store :bar
  #   def get_baz
  #     bar[:baz]
  #   end
  # end
  #
  # Foo.bar[:baz] = 1
  # assert Foo.new.get_baz == 1
  #
  # @param [Symbol] accessor name
  # @param [Block] default value creator
  def self.class_store(name, &create_default)
    define_method(name) do
      default = create_default.call if create_default
      default ||= {}
      self.class._class_store[name] ||= default
    end
    define_singleton_method(name) do
      default = create_default.call if create_default
      default ||= {}
      _class_store[name] ||= default
    end
  end

end
