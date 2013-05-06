
module PuavoRest
# Just for example here
class Users < LdapBase

  use Credentials::BasicAuth
  use Credentials::BootServer

  # Return users in a organisation
  get "/:organisation/users" do
    "current cred #{ env["PUAVO_CREDENTIALS"] }"
  end

end
end

