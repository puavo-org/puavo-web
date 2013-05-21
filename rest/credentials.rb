require "puavo"

module PuavoRest

# Various auth classes for acquiring login credentials.
module Credentials

class AuthBase

  def skip(env, options)
    options[:skip] && options[:skip].to_s.upcase == env["REQUEST_METHOD"].upcase
  end

  def call(env, options={})
    return if skip(options, env)
    acquire(env)
  end

end

# Get user credentials from Basic Auth
class BasicAuth < AuthBase

  def acquire(env)
    return if not env["HTTP_AUTHORIZATION"]
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

# If PuavoRest is running on a boot server use the credentials of the server.
# Can be used to make public resources on the school network.
class BootServer < AuthBase
  def acquire(env)
    if CONFIG["bootserver"]
      {
        :username => PUAVO_ETC.ldap_dn,
        :password => PUAVO_ETC.ldap_password
      }
    end
  end
end


end
end
