
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
      [err.http_code, err.headers, [err.to_json]]
    end
  end
end

end
