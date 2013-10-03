require 'rack/rewrite'

# Rack middleware for faking virtual hosts with url prefixes
#
# Syntax is following:
#
#     /VirtualHostBase/<scheme>/<host>:<port><path>
#
# When this middleware is enabled for example following request
#
#     GET http://localhost:8080/VirtualHostBase/http/fakedomain:1234/v3/users/bob
#
# will be converted to following request
#
#     GET http://fakehost:1234/v3/users/bob
#
# This is used to build correct uris inside the application when it is run
# under reverse proxies such as nginx. It's also usefull for testing.
#
# Inspired by the "Virtual Host Monster" in Zope
#
class VirtualHostBase < Rack::Rewrite
  def initialize(app)
    super(app) do
      rewrite %r{/VirtualHostBase/([a-z]+)/([a-z0-9\.-]+):([0-9]+)(\/.+$)}, lambda { |match, env|
        url, scheme, host, port, path = match.to_a

        env["REQUEST_PATH"] = path
        env["HTTP_HOST"] = env["SERVER_NAME"] = host
        env["SERVER_PORT"] = port
        env["rack.url_scheme"] = scheme
        path
      }
    end
  end
end
