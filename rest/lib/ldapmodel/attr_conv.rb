require "set"

# ldap attribute conversions
class LdapModel
  class_store :pretty2ldap
  class_store :ldap2pretty
  class_store :attr_options
  class_store :skip_serialize_attrs
  class_store :computed_attributes
  class_store :hooks

  attr_reader :ldap_attr_store
  attr_reader :serialize_attrs

  def initialize(attrs={}, options={})
    @existing = !!options[:existing]
    @ldap_attr_store = options[:store] || {}

    if options[:serialize]
      @serialize_attrs = Set.new(options[:serialize].map{|a| a.to_sym})
    end

    @cache = {}
    @validation_errors = {}
    reset_pending
    update!(attrs)
  end


  def self.before(*states, &hook_block)
    hooks[:before] ||= {}
    states.each do |state|
      (hooks[:before][state.to_sym] ||= []).push(hook_block)
    end
  end

  def new?
    !@existing
  end

  def self.after(*states, &hook_block)
    hooks[:after] ||= {}
    states.each do |state|
      (hooks[:after][state.to_sym] ||= []).push(hook_block)
    end
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
        error = transform.new(self).validate(value)
        if error
          add_validation_error(pretty_name, error[:code], error[:message])
          # Raise type check validation error early here because later it can
          # cause more weird errors during hooks and validation
          assert_validation
        else
          write_raw(ldap_name, transform.new(self).write(value))
        end
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

  def update!(h)
    h.each do |k,v|
      send((k.to_s + "=").to_sym, v)
    end
  end

  def get_raw(ldap_name)
    @ldap_attr_store[ldap_name.to_sym]
  end

  def write_raw(ldap_name, new_val)
    ldap_name = ldap_name.to_sym

    pretty_name = ldap2pretty[ldap_name]
    if pretty_name
      @previous_values[pretty_name] = send(pretty_name)
      @cache[pretty_name] = nil
    end

    @ldap_attr_store[ldap_name] = new_val
    @pending_mods.push(LDAP::Mod.new(LDAP::LDAP_MOD_REPLACE, ldap_name.to_s, new_val))

    new_val
  end

  # Returns true if this value is going to be written to ldap on next save!
  def changed?(pretty_name)
    pretty_name = pretty_name.to_sym
    ldap_name = pretty2ldap[pretty_name]
    if !respond_to?(pretty_name)
      raise NoMethodError, "undefined method `#{ pretty_name }' for #{ self.class }"
    end

    return true if new?
    return false if !@previous_values.key?(ldap_name)
    current_val = send(pretty_name)
    prev_val = @previous_values[pretty_name]
    return current_val != prev_val
  end

  # Append value to ArrayValue attribute. The value is saved immediately
  #
  # @param pretty_name [Symbol] Pretty name of the attribute
  # @param value [Any] Value to be appended to the attribute
  def add(pretty_name, value)
    pretty_name = pretty_name.to_sym
    ldap_name = pretty2ldap[pretty_name]
    transform = attr_options[pretty_name][:transform]

    # if not LdapConverters::ArrayValue or subclass of it
    if !(transform <= LdapConverters::ArrayValue)
      raise "add! can be called only on LdapConverters::ArrayValue values. Not #{ transform }"
    end

    if new?
      raise "Cannot call add on new models. Just set the attribute directly"
    end

    if @previous_values[pretty_name].nil?
      @previous_values[pretty_name] = send(pretty_name)
    end

    value = transform.new(self).write(value)
    @pending_mods.push(LDAP::Mod.new(LDAP::LDAP_MOD_ADD, ldap_name.to_s, value))
    @cache[pretty_name] = nil
    current_val = @ldap_attr_store[ldap_name.to_sym]
    @ldap_attr_store[ldap_name.to_sym] = Array(current_val) + value
  end

  def create!(_dn=nil)
    if @existing
      raise "Cannot call create! on existing model"
    end

    run_hook :before, :create
    validate!("Creating")

    _dn = dn if _dn.nil?

    mods = @pending_mods.select do |mod|
      mod.mod_type != "dn"
    end

    res = self.class.ldap_op(:add, dn, mods)
    reset_pending
    @existing = true

    run_hook :after, :create

    res
  end

  def save!
    return create! if !@existing

    run_hook :before, :update
    validate!("Updating")

    res = self.class.ldap_op(:modify, dn, @pending_mods)
    reset_pending

    run_hook :after, :update

    res
  end

  # Add validation error. Can be used only in hooks
  #
  # @param attr [Symbol] Attribute name this error relates to
  # @param code [Symbol] Unique symbol for this name
  # @param message [String] Human readable message for this error
  def add_validation_error(attr, code, message)
    current = @validation_errors[attr.to_sym] ||= []
    current = current.select{|err| err[:code] != code}
    current.push(
      :code => code,
      :message => message
    )
    current = @validation_errors[attr.to_sym] = current
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
    h = nil
    _serialize_attrs = nil

    if other.kind_of?(self.class)
      h = other.ldap_attr_store
      _serialize_attrs = other.serialize_attrs
    else
      h = other # Assume something Hash like
    end

    _ldap_attrs = @ldap_attr_store.dup
    h.each do |pretty_name, value|
      _ldap_attrs[pretty2ldap[pretty_name.to_sym]] = value
    end

    self.class.new({}, {
      :serialize => _serialize_attrs,
      :store => _ldap_attrs
    })
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

  def validate
  end

  def validate_unique(pretty_name)
    return if !changed?(pretty_name)
    ldap_name = pretty2ldap[pretty_name.to_sym]
    val = Array(get_raw(ldap_name)).first
    if self.class.by_attr(pretty_name, val)
      add_validation_error(pretty_name, "#{ pretty_name.to_s }_not_unique".to_sym, "#{ pretty_name }=#{ val } is not unique")
    end
  end

  def assert_validation(message=nil)
    return if @validation_errors.empty?
    errors = @validation_errors
    @validation_errors = {}
    raise ValidationError, {
      :message => message || "Validation error",
      :className => self.class.name,
      :dn => dn,
      :invalid_attributes => errors
    }
  end

  def validate!(message=nil)
    validate
    assert_validation(message)
  end


  private

  def run_hook(pos, event)
    if hooks[pos] && hooks[pos][event]
      hooks[pos][event].each{|hook| instance_exec(&hook)}
    end
  end

  def reset_pending
    @pending_mods = []
    @previous_values = {}
  end

end
