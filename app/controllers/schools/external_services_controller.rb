class Schools::ExternalServicesController < ExternalServicesBase
  def show
    # Don't show services that aren't active in this school (and aren't
    # activated on organisation-level)
    organisation_activated = Array(LdapOrganisation.current.puavoActiveService).map { |dn| dn.to_s }.to_set

    activated = Array(@school.puavoActiveService).map { |dn| dn.to_s }.to_set
    activated += organisation_activated

    @external_services.reject! { |e| !activated.include?(e[:dn]) }

    @external_services.each do |e|
      e[:org_level] = organisation_activated.include?(e[:dn])
    end

    @is_school = true

    respond_to do |format|
      format.html # show.html.erb
    end
  end
end
