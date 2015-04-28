
module PuavoRest
class Organisations < LdapSinatra

  post "/v3/refresh_organisations" do
    Organisation.refresh
  end

  def require_admin!
    if not User.current.admin?
      raise Unauthorized, :user => "Sorry, only administrators can access this resource."
    end
  end

  def require_admin_or_not_people!
    return if not LdapModel.settings[:credentials][:dn].to_s.downcase.match(/people/)

    require_admin!
  end

  get "/v3/organisations" do
    auth :basic_auth, :kerberos
    require_admin_or_not_people!

    Organisation.refresh
    LdapModel.setup(:credentials => CONFIG["server"]) do
      json Organisation.all
    end
  end

  get "/v3/current_organisation" do
    auth :basic_auth, :kerberos
    require_admin_or_not_people!

    Organisation.refresh
    json Organisation.current
  end

  get "/v3/organisations/:domain" do
    auth :basic_auth, :kerberos
    require_admin_or_not_people!

    Organisation.refresh
    json Organisation.by_domain(params[:domain])
  end

end
end
