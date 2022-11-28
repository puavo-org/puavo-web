class OrganisationExternalServicesController < ExternalServicesBase
  def show
    return if redirected_nonowner_user?

    # Don't show services that aren't active in this organisation
    activated = Array(LdapOrganisation.current.puavoActiveService).map { |dn| dn.to_s }.to_set
    @external_services.reject! { |e| !activated.include?(e[:dn]) }

    respond_to do |format|
      format.html # show.html.erb
    end
  end
end
