require "pstore"

module PuavoRest

# Writeable local store. Since ldap connection is read only on boot servers we
# need some simple store we can write to.. Here's simple Pstore wrapper.
class LocalStore

  def initialize(path)
    FileUtils.mkdir_p File.dirname(path)
    @path = path
    @pstore = PStore.new(path, true)
    @pstore.ultra_safe = true
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
    @pstore.transaction do
      @pstore[key] = data
    end
    data
  end

  # Get server info for hostname
  #
  # @param key [String]
  # @return [Hash]
  def get(key)
    @pstore.transaction(true) do
      @pstore[key]
    end
  end

  def delete(key)
    @pstore.transaction do
      @pstore.delete key
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
    @pstore.transaction(true) do
      @pstore.roots.each do |k|
        if block.arity == 1
          block.call @pstore[k]
        else
          block.call k, @pstore[k]
        end
      end
    end
  end

  def destroy
    @pstore =nil
    File.unlink(@path)
  end

end
end
