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
  def self.class_store(name)
    _class_store[name] = {}
    define_method(name) do
      self.class._class_store[name]
    end
    define_singleton_method(name) do
      _class_store[name]
    end
  end

  # copy attributes to inherited subclasses
  def self.inherited(subclass)
    _class_store.keys.each do |k|
      subclass._class_store[k] ||= {}
      subclass._class_store[k].merge!(_class_store[k])
    end
  end

end
