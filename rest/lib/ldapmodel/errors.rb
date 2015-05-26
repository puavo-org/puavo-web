class JSONError < Exception

  attr_accessor :meta

  # @param [String, Hash] error message
  # @option message :user Error message that is displayed to requesting user
  # @option message :mgs Internal error message for stack traces
  def initialize(message, meta=nil)
    @meta = {}

    if message.kind_of?(Hash)
      @meta = message
      message = message[:msg] || message[:message] || message[:user]
    else
      @meta = meta || {}
    end

    super(message)
    @message = message

  end

  def http_code
    500
  end

  def headers
   {"Content-Type" => "application/json"}
  end

  def as_json
    res = {
      :error => {
        :code => self.class.name.split(":").last
      }
    }
    if @meta[:user]
      res[:error][:message] = @meta[:user]
    end
    res
  end

  def to_json
    as_json.to_json
  end

end

class ValidationError < JSONError
  def http_code
    400
  end

  def to_s
    dn = ""
    if @meta[:dn]
      dn = "(#{ @meta[:dn] })"
    end

    msg = @message
    msg += "\n  Invalid attributes for #{ @meta[:className] } #{ dn }:\n"
    Array(@meta[:invalid_attributes]).each do |attr, errors|
      errors.each do |error|
        msg += "    * #{ attr }: #{ error[:message] }"
      end
    end
    msg + "\n"
  end

  def as_json
    parent = super
    parent[:error][:meta] = {
      :invalid_attributes => @meta[:invalid_attributes]
    }
    parent
  end
end

class NotFound < JSONError
  def http_code
    404
  end
end

class BadInput < JSONError
  def http_code
    400
  end
end

class BadCredentials < JSONError
  def http_code
    401
  end
end

class LdapError < JSONError
  def http_code
    500
  end
end

class KerberosError < JSONError
  def http_code
    401
  end
end

class InternalError < JSONError
  def http_code
    500
  end
end

class NotImplemented < JSONError
  def http_code
    501
  end
end

class LdapError < JSONError
  def http_code
    500
  end

  def original_error
    @meta[:original_error]
  end
end

class Unauthorized < JSONError
  def http_code
    401
  end

  def headers
    super.merge "WWW-Authenticate" => "Negotiate"
 end
end
