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


  # Register block to be executed on the given states
  #
  # @param [Symbol] *states :create, :update or :validate
  # @param [block] hook_block Hook block to be registered
  # @yield lol jee
  def self.before(*states, &hook_block)
    hooks[:before] ||= {}
    states.each do |state|
      (hooks[:before][state.to_sym] ||= []).push(hook_block)
    end
  end

  # (see .before)
  def self.after(*states, &hook_block)
    hooks[:after] ||= {}
    states.each do |state|
      (hooks[:after][state.to_sym] ||= []).push(hook_block)
    end
  end

  # Returns true if the model is present in LDAP
  # @return [Boolean]
  def new?
    !@existing
  end



  # Define conversion between LDAP attribute and the JSON attribute. This will
  # create a getter method named by the `pretty_name` param
  #
  # @param ldap_name [Symbol] LDAP attribute to transform
  # @param pretty_name [Symbol] Pretty name for the attribute which will used the access the value from the model instance
  # @param options [Hash, LdapConverters::Base] A LdapConverters::Base subclass or an options hash
  # @option options [LdapConverters::Base] :transform
  # @option options [Object] :default Default value for the attribute
  # @param transform [Block] Block used to transform the attribute value when reading
  # @yieldparam [Array, Object] value Raw value from ldap. Usually an Array
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
  # @param [Symbol] attr method to be called in serializations
  # @param [Symbol] serialization_name Change the name in serialization
  def self.computed_attr(attr, serialize_name=nil)
    computed_attributes[attr.to_sym] = serialize_name || attr
  end

  # Skip this attribute(s) from serializations such as `to_hash` and `to_json`
  #
  # @param attrs [Symbol, Array<Symbol>]
  def self.skip_serialize(*attrs)
    attrs.each { |a| skip_serialize_attrs[a.to_sym] = true }
  end

  # @param [Symbol] pretty_name Get the transformed attribute value of this model
  # @return [Object]
  def get_own(pretty_name)
    pretty_name = pretty_name.to_sym
    return @cache[pretty_name] if not @cache[pretty_name].nil?

    ldap_name = pretty2ldap[pretty_name]
    default_value = attr_options[pretty_name][:default]

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

    @cache[pretty_name] = transform(pretty_name, :read, value)
  end


  # Transform value using the attribute transformer
  #
  # @param pretty_name [Symbol] Pretty name of the attribute
  # @param method [Symbol] :read or :write
  # @param value [Object] value to transform
  def transform(pretty_name, method, value)
    transformer = attr_options[pretty_name][:transform]
    transformer.new(self).send(method, value)
  end

  # @param [Hash] h Update model attributes from hash
  def update!(h)
    h.each do |k,v|
      send((k.to_s + "=").to_sym, v)
    end
  end

  # @param [Symbol] ldap_name Get raw ldap value by ldap attribute name
  # @return [Object]
  def get_raw(ldap_name)
    @ldap_attr_store[ldap_name.to_sym]
  end

  # Write raw ldap value
  #
  # @param [Symbol] ldap_name LDAP attribute name
  # @param [Object] new_val Value to be written
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

  # Returns true if this value is going to be written to ldap on next #save! call
  # @param [Symbol] pretty_name
  # @return [Boolean]
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

  # Append value to {LdapConverters::ArrayValue} attribute. Value is persisted on
  # the next {#save!} call
  #
  # @param pretty_name [Symbol] Pretty name of the attribute
  # @param value [Object] Value to be appended to the attribute
  def add(pretty_name, value)
    pretty_name = pretty_name.to_sym
    ldap_name = pretty2ldap[pretty_name]
    transform = attr_options[pretty_name][:transform]

    # if not LdapConverters::ArrayValue or subclass of it
    if !(transform <= LdapConverters::ArrayValue)
      raise "#add(...) can be called only on LdapConverters::ArrayValue values. Not #{ transform }"
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

  # Remove value from {LdapConverters::ArrayValue} attribute. Deletion is
  # persisted on the next {#save!} call
  #
  # @param pretty_name [Symbol] Pretty name of the attribute
  # @param value [Object] Value to be removed from the attribute
  def remove(pretty_name, value)
    pretty_name = pretty_name.to_sym
    ldap_name = pretty2ldap[pretty_name]
    transform = attr_options[pretty_name][:transform]

    # if not LdapConverters::ArrayValue or subclass of it
    if !(transform <= LdapConverters::ArrayValue)
      raise "#remove(...) can be called only on LdapConverters::ArrayValue values. Not #{ transform }"
    end

    if new?
      raise "#remove(...) is not supported on new models. Just set the attribute"
    end

    if @previous_values[pretty_name].nil?
      @previous_values[pretty_name] = send(pretty_name)
    end

    # Transform to the ldap format
    value = transform.new(self).write(value).first

    @pending_mods.push(LDAP::Mod.new(LDAP::LDAP_MOD_DELETE, ldap_name.to_s, [value]))
    @cache[pretty_name] = nil
    current_val = @ldap_attr_store[ldap_name.to_sym]
    @ldap_attr_store[ldap_name.to_sym] = Array(current_val).reject do |v|
      v == value
    end
  end



  # Save new model to LDAP
  # @param [String] _dn Set to use custom dn
  def create!(_dn=nil)
    if @existing
      raise "Cannot call create! on existing model"
    end

    validate!("Creating")

    run_hook :before, :create

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

  # Save changes to LDAP
  def save!
    return create! if !@existing

    validate!("Updating")

    run_hook :before, :update
    res = self.class.ldap_op(:modify, dn, @pending_mods)
    reset_pending
    run_hook :after, :update

    res
  end

  # Add validation error. Error will be raised on the next {#save!} call
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

  # Returns true when the model has unsaved changes in attributes
  #
  # @return [Boolean]
  def dirty?
    !@pending_mods.empty?
  end

  # @deprecated
  def [](pretty_name)
    send(pretty_name.to_sym)
  end

  # @deprecated
  def []=(pretty_name, value)
    set(pretty_name, value)
  end

  # Returns trur when the model has no values
  # @return [Boolean]
  def empty?
    @ldap_attr_store.empty?
  end

  # @return [Array<Symbol>] LDAP attributes that will be converted
  def self.ldap_attrs
    ldap2pretty.keys
  end

  # Set attribute using the original ldap attribute
  #
  # @param [Symbol] ldap_name
  # @param [Object] value
  def ldap_set(ldap_name, value)
    return if ldap2pretty[ldap_name.to_sym].nil?
    @ldap_attr_store[ldap_name.to_sym] = value
  end

  # @deprecated
  def set(pretty_name, value)
    @cache[pretty_name.to_sym] = value
  end

  # Merge hash of ldap attributes to this model
  # @param [Hash] hash
  def ldap_merge!(hash)
    hash.each do |ldap_name, value|
      ldap_set(ldap_name, value)
    end
    self
  end

  # Merge value from other LdapModel to this one
  # @param [LdapModel] other
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

  # Convert model to Hash
  # @return Hash
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

  # @return Object
  def as_json(*)
    to_hash
  end

  # @return String
  def to_json(*)
    as_json.to_json
  end

  computed_attr :object_model
  def object_model
    self.class.to_s
  end

  # Validation method called before saving. Override it and call
  # {#add_validation_error} for any errors
  def validate
  end

  # Validate uniqueness of an attribute
  # @param [Symbol] pretty_name
  def validate_unique(pretty_name)
    return if !changed?(pretty_name)
    ldap_name = pretty2ldap[pretty_name.to_sym]
    val = Array(get_raw(ldap_name)).first
    if self.class.by_attr(pretty_name, val)
      add_validation_error(pretty_name, "#{ pretty_name.to_s }_not_unique".to_sym, "#{ pretty_name }=#{ val } is not unique")
    end
  end

  # Raises {ValidationError} if {#add_validation_error} was called at least once
  # @param [String] message Optional custom error message
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

  # Run hooks and validations. May raise {ValidationError}
  # @param [String] message Optional custom error message
  def validate!(message=nil)
    run_hook :before, :validate
    validate
    assert_validation(message)
    run_hook :after, :validate
  end

  def self.pretty2ldap!(pretty_name)
    ldap_attr = pretty2ldap[pretty_name.to_sym]
    if ldap_attr.nil?
      # Would compile to invalid ldap search filter. Throw early with human
      # readable error message
      raise "Invalid pretty attribute #{ pretty_name } for #{ self }"
    end
    ldap_attr
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
