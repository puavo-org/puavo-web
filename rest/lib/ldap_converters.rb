module LdapConverters

  # Base class for LDAP value conversions
  class Base
    attr_reader :model

    def initialize(model)
      @model = model
    end

    # Override in a subclass
    def validate(value)
    end

    # Override in a subclass
    def write(write)
    end

    # Override in a subclass
    def read()
    end

  end


  # Force LDAP value to be a single value instead of Array
  class SingleValue < Base
    def read(v)
      Array(v).first
    end
    def write(v)
      Array(v)
    end
  end

  # Force LDAP value to be single Fixnum number
  class Number < Base
    def read(v)
      if v.nil?
        return nil
      end

      if v.kind_of?(Array) && v.empty?
        return nil
      end

      Array(v).first.to_i
    end
    def write(v)
      Array(v.to_s)
    end
  end

  # Force LDAP value to be an Array
  class ArrayValue < Base
    def read(v)
      Array(v)
    end
    def write(v)
      Array(v)
    end
    def validate(v)
      return if v.kind_of?(Array)
      return {
        :code => :invalid_type,
        :message => "Value must be Array like not #{ v.class.name }"
      }
    end
  end

  # Convert string style booleans "TRUE" and "FALSE" to real ruby booleans
  class StringBoolean < Base
    def read(value)
      case Array(value).first
      when "TRUE"
        true
      when "FALSE"
        false
      else
        nil
      end
    end

    def write(value)
      if value
        "TRUE"
      else
        "FALSE"
      end
    end

  end

  # Convert LDAP Array of JSON strings to array of ruby objects
  class ArrayOfJSON < ArrayValue

    def read(value)
      Array(value).map do |n|
        begin
          JSON.parse(n)
        rescue JSON::ParserError
          JSON::ParserError
        end
      end.select{|v| v != JSON::ParserError}
    end

    def write(value)
      Array(value).map{|v| v.to_json}
    end

  end


  # @deprecated Use {LdapConverters::StringBoolean} instead.
  def self.string_boolean
    lambda do |value|
      case Array(value).first
      when "TRUE"
        true
      when "FALSE"
        false
      else
        nil
      end
    end
  end

  # @deprecated Use {LdapConverters::ArrayOfJSON} instead.
  def self.json
    lambda do |networks|
      Array(networks).map do |n|
        begin
          JSON.parse(n)
        rescue JSON::ParserError
          # Legacy data is not JSON. Just ignore...
        end
      end.compact
    end
  end

  # @deprecated Use {LdapConverters::ArrayOfJSON} instead.
  def self.parse_wlan
    json
  end
end
