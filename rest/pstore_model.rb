
module PuavoRest

# Abstract class for local persistent models
class PstoreModel

  def initialize(path)
    FileUtils.mkdir_p File.dirname(path)
    @store = PStore.new(path, true)
    @store.ultra_safe = true
  end

  # Create instance from organisation domain using PuavoRest::CONFIG
  #
  # @param organisation_domain [String]
  def self.from_domain(organisation_domain, *args)
    path = File.join(
      CONFIG["ltsp_server_data_dir"],
      "#{ self.name }.#{ organisation_domain }.pstore"
    )
    self.new(path, *args)
  end

  # Save attributes to key
  #
  # @param key [String]
  # @param data [Hash]
  def set(key, data)
    @store.transaction do
      @store[key] = data
    end
    data
  end

  # Get server info for hostname
  #
  # @param key [String]
  # @return [Hash]
  def get(key)
    @store.transaction(true) do
      @store[key]
    end
  end

  # Return all known keys
  # @return [Array]
  def all
    a = []
    each { |v| a.push  v }
    a
  end

  def each(&block)
    @store.transaction(true) do
      @store.roots.each do |k|
        if block.arity == 1
          block.call @store[k]
        else
          block.call k, @store[k]
        end
      end
    end
  end
end
end
