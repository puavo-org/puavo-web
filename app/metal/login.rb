# Allow the metal piece to run in isolation
require(File.dirname(__FILE__) + "/../../config/environment") unless defined?(Rails)

class Login
  def self.call(env)
    if env["HTTP_HOST"] =~ /weblogin/
      engine = Haml::Engine.new("%p Puavo Login")
      [200, {"Content-Type" => "text/html"}, [ engine.render ]]
    else
      [404, {"Content-Type" => "text/html"}, ["Not Found"]]
    end
  end
end

