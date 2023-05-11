require "puavo"

require "thread"
require "base64"
require "gssapi"
require "gssapi/lib_gssapi"

require_relative "./krb5-gssapi"

module PuavoRest

class PuavoSinatra < Sinatra::Base

  def basic_auth
    return if not env["HTTP_AUTHORIZATION"]
    type, data = env["HTTP_AUTHORIZATION"].split(" ", 2)
    if type == "Basic"
      plain = Base64.decode64(data)
      username, password = plain.split(":")

      credentials = { :password => password  }
      if LdapModel.is_dn(username)
        credentials[:dn] = username
      else
        credentials[:username] = username
      end
      rlog.info("using basic auth #{ credentials[:dn] ? "with dn" : "with uid" }")
      return credentials
    end
  end

  def from_post
    return if env["REQUEST_METHOD"] != "POST"
    return {
      :username => params["username"].split("@").first,
      :password => params["password"]
    }
  end

  def pw_mgmt_server_auth
    if CONFIG["password_management"]
      return {
        :dn => PUAVO_ETC.ds_pw_mgmt_dn,
        :password => PUAVO_ETC.ds_pw_mgmt_password
      }
    else
      rlog.error('cannot use password management auth on cloud or bootserver installation')
      return
    end
  end

  # Email address changing/verification using the public profile form
  def email_mgmt_server_auth
    if CONFIG['email_management']
      return {
        :dn => PUAVO_ETC.ds_email_mgmt_dn,
        :password => PUAVO_ETC.ds_email_mgmt_password
      }
    else
      rlog.error('cannot use email management auth on cloud or bootserver installation')
      return
    end
  end

  # Pick bootserver credentials when Header 'Authorization: Bootserver' is set
  def server_auth
    if not CONFIG["bootserver"]
      rlog.error('cannot use bootserver auth on cloud installation')
      return
    end

    if env["HTTP_AUTHORIZATION"].to_s.downcase == "bootserver"
      return CONFIG["server"]
    end
  end

  # In an old version bootserver authentication was picked when no other
  # authentication methods were available. But that conflicted with the
  # kerberos authentication. This is now legacy and will removed in future.
  def legacy_server_auth
    if not CONFIG["bootserver"]
      rlog.error('cannot use bootserver auth on cloud installation')
      return
    end

    # In future we will only use server based authentication if 'Authorization:
    # Bootserver' is set. Otherwise we will assume Kerberos authentication.
    if env["HTTP_AUTHORIZATION"].to_s.downcase != "bootserver"
      rlog.warn("WARNING!  Using deprecated bootserver authentication without the Header 'Authorization: Bootserver'")
    end

    ## Helper to sweep out lecagy calls from tests
    # if ENV["RACK_ENV"] == "test"
    #   puts "Legacy legacy_server_auth usage from:"
    #   puts caller[0..5]
    #   puts
    # end

    return CONFIG["server"]
  end


  # This must be always the last authentication option because it is
  # initialized by the server by responding 401 Unauthorized
  def kerberos
    return if env["HTTP_AUTHORIZATION"].nil?
    auth_key = env["HTTP_AUTHORIZATION"].split()[0]
    return if auth_key.to_s.downcase != "negotiate"
    rlog.info("using kerberos authentication")
    return {
      :kerberos => Base64.decode64(env["HTTP_AUTHORIZATION"].split()[1])
    }
  end

  def auth(*auth_methods)
    if auth_methods.include?(:kerberos) && auth_methods.include?(:legacy_server_auth)
      raise "legacy server auth and kerberos cannot be used on the same resource"
    end

    auth_method = nil

    auth_methods.each do |method|
      credentials = send(method)
      next if !credentials

      if credentials[:dn].nil? && credentials[:username]
        credentials[:dn] = LdapModel.setup(:credentials => CONFIG["server"]) do
          User.resolve_dn(credentials[:username])
        end
      end

      if credentials[:dn].nil? && credentials[:kerberos].nil?
        puts "Cannot resolve #{ credentials[:username].inspect } to DN"
        raise Unauthorized,
          :user => "Could not create ldap connection. Bad/missing credentials. #{ auth_methods.inspect }",
          :meta => {
            :username => credentials[:username],
          }
      end

      credentials[:auth_method] = method
      auth_method = method
      LdapModel.setup(:credentials => credentials)
      break
    end


    if not LdapModel.connection
      raise Unauthorized,
        :user => "Could not create ldap connection. Bad/missing credentials. #{ auth_methods.inspect }"
    end

    log_creds = LdapModel.settings[:credentials].dup
    log_creds.delete(:kerberos)
    log_creds.delete(:password)
    self.rlog = rlog.merge(:credentials => log_creds)
    rlog.info("authenticated through '#{ auth_method }'")
  end

end
end
