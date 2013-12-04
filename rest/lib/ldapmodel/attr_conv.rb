
# ldap attribute conversions
class LdapModel
  class_store :pretty2ldap
  class_store :ldap2pretty
  class_store :converters
  class_store :ignored_attributes
  class_store(:computed_attributes){ [] }
  attr_reader :ldap_attr_store

  def initialize(ldap_attr_store={})
    @ldap_attr_store = ldap_attr_store
    @cache = {}
  end


  # Define conversion between LDAP attribute and the JSON attribute
  #
  # @param ldap_name [Symbol] LDAP attribute to convert
  # @param pretty_name [Symbol] Value conversion block. Default: Get first array item
  # @param convert [Block] Use block to
  # @see convert
  def self.ldap_map(ldap_name, pretty_name, default_value=nil, &convert)
    pretty_name = pretty_name.to_sym
    ldap_name = ldap_name.to_sym
    pretty2ldap[pretty_name] = ldap_name
    ldap2pretty[ldap_name] = pretty_name

    converters[ldap_name] = {
      :default => default_value,
      :convert => convert
    }

    define_method pretty_name do
      get_own(pretty_name)
    end
  end

  # A method that will be executed and added to `to_hash` and `to_json`
  # conversions of this models
  def self.computed_attr(*attrs)
    attrs.each { |a| computed_attributes.push(a.to_sym) }
  end

  # Ignore one or more ldap_map attributes from `to_hash` and `to_json`
  # serializations
  def self.ignore_attr(*attrs)
    attrs.each { |a| ignored_attributes[a.to_sym] = true }
  end

  def get_own(pretty_name)
    pretty_name = pretty_name.to_sym
    return @cache[pretty_name] if not @cache[pretty_name].nil?

    ldap_name = pretty2ldap[pretty_name]
    default_value = converters[ldap_name][:default]
    convert = converters[ldap_name][:convert]

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

    if convert
      value = instance_exec(value, &convert)
    else
      value = Array(value).first
    end

    @cache[pretty_name] = value
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
      if !ignored_attributes[pretty_name.to_sym]
        h[pretty_name.to_s] = send(pretty_name)
      end
    end
    computed_attributes.each do |attr|
      h[attr.to_s] = send(attr)
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

end
