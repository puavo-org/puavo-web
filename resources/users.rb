
module PuavoRest
# Just for example here
class Users < LdapSinatra

  auth Credentials::BasicAuth
  auth Credentials::BootServer

  # Return users in a organisation
  get "/:organisation/users" do
    "current cred #{ env["PUAVO_CREDENTIALS"] }"
  end

end
end

