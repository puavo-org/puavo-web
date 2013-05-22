module PuavoRest

# Possible error responses in PuavoRest.
#
# Example response:
#
#    {
#      "error": {
#        "code": <[String] error code>,
#        "message": <[String] human readable error message>,
#
#      }
#    }
#
module ErrorMethods

  # Halt request with not_found code
  # @param msg [String] Human readable description of the situation
  # @return [HTTP response]
  def bad_credentials(msg="")
    json_format(401, "bad_credentials", msg)
  end

  # Halt request with not_found code
  # @param msg [String] Human readable description of the situation
  # @return [HTTP response]
  def not_found(msg="")
    json_format(404, "not_found", msg)
  end

  private

  def json_format(status, code, msg)
    halt status, {"Content-Type" => "application/json"}, {
      "error" => {
        "code" => code,
        "message" => msg
      }
    }.to_json
  end

end
end
