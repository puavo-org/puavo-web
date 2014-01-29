
module PuavoRest

class User < LdapModel

  ldap_map :dn, :dn
  ldap_map :uid, :username
  ldap_map(:uidNumber, :uid_number){ |v| Array(v).first.to_i }
  ldap_map(:gidNumber, :gid_number){ |v| Array(v).first.to_i }
  ldap_map :sn, :last_name
  ldap_map :givenName, :first_name
  ldap_map :mail, :email
  ldap_map :puavoEduPersonAffiliation, :user_type
  ldap_map :puavoId, :puavo_id
  ldap_map :puavoSchool, :school_dn
  ldap_map :preferredLanguage, :preferred_language
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
    by_attr(:username, username)
  end

  def self.resolve_dn(username)
    dn = raw_filter("(uid=#{ escape username })", ["dn"])
    if dn && !dn.empty?
      dn.first["dn"].first
    end
  end

  def self.profile_image(uid)
    raw_filter("(uid=#{ escape uid })", ["jpegPhoto"]).first["jpegPhoto"]
  end

  def organisation
    User.organisation
  end

  # Cached school query
  def school
    return @school if @school
    return if school_dn.nil?
    @school = School.by_dn(school_dn)
  end

  def preferred_language
    if get_own(:preferred_language).nil? && school
      school.preferred_language
    else
      get_own(:preferred_language)
    end
  end

  def admin?
    user_type == "admin"
  end

  def groups
    @groups ||= Group.by_user_dn(dn)
  end

  computed_attr :domain_username
  def domain_username
    "#{ username }@#{ organisation.domain }"
  end

  computed_attr :homepage
  def homepage
    if school
      school.homepage
    end
  end

  def server_user?
    dn == CONFIG["server"][:dn]
  end

  def self.current
    return settings[:credentials_cache][:current_user] if settings[:credentials_cache][:current_user]

    user_credentials = settings[:credentials]

    if user_credentials[:dn]
      user = User.by_dn(user_credentials[:dn])
    elsif user_credentials[:username]
      user = User.by_username(user_credentials[:username])
    end

    settings[:credentials_cache][:current_user] = user
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

  get "/v3/whoami" do
    auth :basic_auth, :kerberos
    user = User.current.to_hash
    json user.merge("organisation" => LdapModel.organisation.to_hash)
  end

end
end

