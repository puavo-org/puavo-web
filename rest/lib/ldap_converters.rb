module LdapConverters

  class Base
    attr_reader :model

    def initialize(model)
      @model = model
    end
  end


  class SingleValue < Base
    def read(v)
      Array(v).first
    end
    def write(v)
      Array(v)
    end
  end

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

  class ArrayValue < Base
    def read(v)
      Array(v)
    end
    def write(v)
      Array(v)
    end
  end

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

  def self.parse_wlan
    json
  end
end
