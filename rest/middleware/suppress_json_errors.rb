
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
      message = "ERROR: #{ err.message }"
      if STDIN.tty?
	STDERR.puts message.colorize(:red)
      else
	STDERR.puts message
      end

      [err.http_code, err.headers, [err.to_json]]
    end
  end
end

end
