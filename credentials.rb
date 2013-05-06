module PuavoRest

class Credentials

  def initialize(app)
    @app = app
  end

  def call(env)
    env["PUAVO_CREDENTIALS"] ||= acquire(env)
    @app.call(env)
  end

end

class BasicAuthCredentials < Credentials
  def acquire(env)
    type, data = env["HTTP_AUTHORIZATION"].split(" ")
    if type == "Basic"
      plain = Base64.decode64(data)
      username, password = plain.split(":")
      {
        :username => username,
        :password => password
      }
    end
  end
end

class ServerCredentials < Credentials
  def acquire(env)
    {
      :username => "uid=admin,o=puavo",
      :password => "password"
    }
  end
end

end
