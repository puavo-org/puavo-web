
module PuavoRest

class User < LdapHash

  ldap_map :dn, :dn
  ldap_map :uid, :username
  ldap_map :sn, :last_name
  ldap_map :givenName, :first_name
  ldap_map :mail, :email
  ldap_map(:jpegPhoto, :profile_image_link) do |image_data|
    if image_data
      link "/v3/users/#{ self["username"] }/profile.jpg"
    end
  end

  def self.ldap_base
    "ou=People,#{ organisation["base"] }"
  end

  # aka by_uuid
  def self.by_username(username)
    filter("(uid=#{ escape username })").first
  end

  def self.resolve_dn(username)
    raw_filter("(uid=#{ escape username })", ["dn"]).first["dn"].first
  end

  def self.profile_image(uid)
    raw_filter("(uid=#{ escape uid })", ["jpegPhoto"]).first["jpegPhoto"]
  end

end

class Users < LdapSinatra


  # Return users in a organisation
  get "/v3/users" do
    auth :basic_auth, :kerberos

    json User.all
  end

  # Return users in a organisation
  get "/v3/users/:username" do
    auth :basic_auth, :kerberos

    json User.by_username(params["username"])
  end

  get "/v3/users/:username/profile.jpg" do
    auth :basic_auth, :kerberos

    image = User.profile_image(params["username"])
    if image
      content_type "image/jpeg"
      image
    else
      raise NotFound, :user => "#{ params["username"] } has no profile image"
    end
  end

end
end

