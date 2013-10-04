class LdapModel
  # Store for ldap attribute mappings
  @@_class_store = {}
  def self._class_store
    @@_class_store[self] ||= {}
  end

  def self.class_store(name)
    define_method(name) do
      self.class._class_store[name] ||= {}
    end
    define_singleton_method(name) do
      _class_store[name] ||= {}
    end
  end

end
