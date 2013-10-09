class LdapModel
  # Store for ldap attribute mappings
  @@_class_store = {}
  def self._class_store
    @@_class_store[self] ||= {}
  end

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
