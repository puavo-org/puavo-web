
require "pstore"
require "fileutils"

module LocalStoreMixin

  def save(key)
    pstore = self.class.setup_local_store
    pstore.transaction do
      pstore[key] = self
    end
  end

  module ClassMethods
    def setup_local_store
      path = File.join(
        PuavoRest::CONFIG["ltsp_server_data_dir"],
        "#{ self.name }.#{ organisation["domain"] }.pstore"
      )
      FileUtils.mkdir_p File.dirname(path)

      pstore = PStore.new(path, true)
      pstore.ultra_safe = true
      pstore
    end

    def load(key)
      pstore = setup_local_store
      pstore.transaction(true) do
        pstore[key]
      end
    end
  end

  def self.included(base)
    base.extend(ClassMethods)
  end

end

