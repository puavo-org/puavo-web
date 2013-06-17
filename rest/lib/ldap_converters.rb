module PuavoRest
class LdapConverters

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

  def self.parse_wlan
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
end
end
