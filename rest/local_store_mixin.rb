
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

    def each(&block)
      pstore = setup_local_store
      pstore.transaction(true) do
        pstore.roots.each do |k|
          if block.arity == 1
            block.call pstore[k]
          else
            block.call k, pstore[k]
          end
        end
      end
    end

    # Return all known keys
    # @return [Array]
    def all
      a = []
      each { |v| a.push  v }
      a
    end
  end

  def self.included(base)
    base.extend(ClassMethods)
  end

end

