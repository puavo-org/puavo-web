
module PuavoRest
  class Authentication < PuavoSinatra


    get "/v3/auth" do
      auth :basic_auth

      user = User.current.to_hash
      json user.merge("organisation" => LdapModel.organisation.to_hash)
    end
  end
end
