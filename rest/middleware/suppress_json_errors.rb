
module PuavoRest

# Middleware to suppress Execeptions inherited from {JSONError}
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
