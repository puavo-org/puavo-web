
require_relative "../lib/error_codes"
module PuavoRest

# Middleware to suppress expected json error messages
class SuppressJSONError
  def initialize(app)
    @app = app
  end

  def call(env)
    begin
      @app.call(env)
    rescue JSONError => err
      if !["production", "test"].include?(ENV["RACK_ENV"])
        # XXX: Cannot use logger here...
        puts "JSONError: #{ err.class }: #{ err.message }"
      end
      [err.http_code, err.headers, [err.to_json]]
    end
  end
end

end
