module PuavoRest

# Various Rack middleware classes for acquiring login credentials.
module Credentials

class Base

  def initialize(app)
    @app = app
  end

  def call(env)
    env["PUAVO_CREDENTIALS"] ||= acquire(env)
    @app.call(env)
  end

end

# Get user credentials from Basic Auth
class BasicAuth < Base
  def acquire(env)
    return if not env["HTTP_AUTHORIZATION"]
    type, data = env["HTTP_AUTHORIZATION"].split(" ")
    if type == "Basic"
      plain = Base64.decode64(data)
      puts "using basic auth credentials"
      username, password = plain.split(":")
      {
        :username => username,
        :password => password
      }
    end
  end
end

# If PuavoRest is running on a boot server use the credentials of the server.
# Can be used to make public resources on the school network.
class BootServer < Base
  def acquire(env)
    # TODO: read from /etc/puavo
    puts "using boot credentials"
    {
      :username => "uid=admin,o=puavo",
      :password => "password"
    }
  end
end


end
end
