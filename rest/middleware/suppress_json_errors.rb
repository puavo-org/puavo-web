
require_relative "../lib/error_codes"
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
      if ENV["RACK_ENV"] != "test"

        message = "#{ err }\n#{ err.backtrace.join("\n") }"
        if STDIN.tty?
          STDERR.puts message.colorize(:red)
        else
          STDERR.puts message
        end
      end

      [err.http_code, err.headers, [err.to_json]]
    end
  end
end

end
