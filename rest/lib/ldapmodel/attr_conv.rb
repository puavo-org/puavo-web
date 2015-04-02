require "set"

# ldap attribute conversions
class LdapModel
  class_store :pretty2ldap
  class_store :ldap2pretty
  class_store :attr_options
  class_store :skip_serialize_attrs
  class_store :computed_attributes

  attr_reader :ldap_attr_store

  def initialize(ldap_attr_store=nil, serialize_attrs=nil)
    @ldap_attr_store = ldap_attr_store || {}
    if serialize_attrs
      @serialize_attrs = Set.new(serialize_attrs.map{|a| a.to_sym})
    end
    @cache = {}
    @pending_mods = []
  end


  # Define conversion between LDAP attribute and the JSON attribute
  #
  # @param ldap_name [Symbol] LDAP attribute to transform
  # @param pretty_name [Symbol] Value conversion block. Default: Get first array item
  # @param options [Hash] with :default and :transform keys
  # @param transform [Block] Use block to
  # @see transform
  def self.ldap_map(ldap_name, pretty_name, options=nil, &transform_block)
    pretty_name = pretty_name.to_sym
    ldap_name = ldap_name.to_sym
    pretty2ldap[pretty_name] = ldap_name
    ldap2pretty[ldap_name] = pretty_name

    mapping_string = "#{ self }.ldap_map(:#{ ldap_name }, :#{ pretty_name })"

    if ![NilClass, Class, Hash].include?(options.class)
      raise "#{mapping_string} has invalid options argument: #{ options.inspect }"
    end


    transform = LdapConverters::SingleValue
    default_value = nil

    if options.class == Hash
      transform = options[:transform] if options[:transform]
      default_value = options[:default]
    elsif options
      transform = options
    end

    if transform_block && transform.class != Class
      raise "#{mapping_string} cannot use both transform instance and transform block"
    end

    if transform_block && transform.class == Class
      # Inherit the transform class and override the read method with the given
      # block
      transform = Class.new(transform)
      transform.send(:define_method, :read, &transform_block)
    end

    attr_options[pretty_name] = {
      :default => default_value,
      :transform => transform
    }

    # Create simple getter for the attribute if no custom one is defined
    if not method_defined?(pretty_name)
      define_method pretty_name do
        get_own(pretty_name)
      end
    end

    setter_method = (pretty_name.to_s + "=").to_sym
    if not method_defined?(setter_method)
      define_method setter_method do |value|
        write_raw(pretty_name, transform.new(self).write(value))
      end
    end
  end


  # A method that will be executed and added to `to_hash` and `to_json`
  # conversions of this models
  def self.computed_attr(attr, serialize_name=nil)
    computed_attributes[attr.to_sym] = serialize_name || attr
  end

  # Skip this attribute(s) from serializations such as `to_hash` and `to_json`
  #
  # @param attr [Symbol or array of Symbols]
  def self.skip_serialize(*attrs)
    attrs.each { |a| skip_serialize_attrs[a.to_sym] = true }
  end

  def get_own(pretty_name)
    pretty_name = pretty_name.to_sym
    return @cache[pretty_name] if not @cache[pretty_name].nil?

    ldap_name = pretty2ldap[pretty_name]
    default_value = attr_options[pretty_name][:default]
    transform = attr_options[pretty_name][:transform]

    value = Array(@ldap_attr_store[ldap_name])

    # String values in our LDAP are always UTF-8
    value = value.map do |item|
      if item.respond_to?(:force_encoding)
        item.force_encoding("UTF-8")
      else
        item
      end
    end

    if Array(value).empty? && !default_value.nil?
      return default_value
    end

    @cache[pretty_name] = transform.new(self).read(value)
  end

  def update(h)
    h.each do |k,v|
      send((k.to_s + "=").to_sym, v)
    end
  end

  def write_raw(pretty_name, value)
    ldap_name = pretty2ldap[pretty_name.to_sym]
    @ldap_attr_store[ldap_name] = value
    @cache[pretty_name] = nil

    @pending_mods.push(LDAP::Mod.new(LDAP::LDAP_MOD_REPLACE, ldap_name.to_s, Array(value)))
    value
  end

  def save!
    res = self.class.connection.modify(dn, @pending_mods)
    @pending_mods = []
    res
  end

  def dirty?
    !@pending_mods.empty?
  end

  def [](pretty_name)
    send(pretty_name.to_sym)
  end

  def []=(pretty_name, value)
    set(pretty_name, value)
  end

  def empty?
    @ldap_attr_store.empty?
  end

  # @return [Array] LDAP attributes that will be converted
  def self.ldap_attrs
    ldap2pretty.keys
  end

  # Set attribute using the original ldap attribute
  #
  # @param [String]
  # @param [any]
  def ldap_set(ldap_name, value)
    return if ldap2pretty[ldap_name.to_sym].nil?
    @ldap_attr_store[ldap_name.to_sym] = value
  end

  def set(pretty_name, value)
    @cache[pretty_name.to_sym] = value
  end

  # Like normal Hash#merge!
  def ldap_merge!(hash)
    hash.each do |ldap_name, value|
      ldap_set(ldap_name, value)
    end
    self
  end

  def merge(other)
    h = other.class == Hash ? other : other.ldap_attr_store
    new_h = @ldap_attr_store.dup
    h.each do |pretty_name, value|
      new_h[pretty2ldap[pretty_name.to_sym]] = value
    end
    self.class.new(new_h)
  end

  def to_hash
    h = {}
    pretty2ldap.each do |pretty_name, _|
      next if @serialize_attrs && !@serialize_attrs.include?(pretty_name)

      if !skip_serialize_attrs[pretty_name.to_sym]
        h[pretty_name.to_s] = send(pretty_name)
      end
    end

    computed_attributes.each do |method_name, serialize_name|
      next if @serialize_attrs && !@serialize_attrs.include?(serialize_name)
      h[serialize_name.to_s] = send(method_name)
    end
    h
  end

  def to_ldap_hash
    @ldap_attr_store.dup
  end

  def as_json(*)
    to_hash
  end

  def to_json(*)
    as_json.to_json
  end

  computed_attr :object_model
  def object_model
    self.class.to_s
  end

end
