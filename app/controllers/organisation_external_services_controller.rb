class OrganisationExternalServicesController < ExternalServicesBase
  def show
    return if redirected_nonowner_user?

    # Don't show services that aren't active in this organisation
    activated = Array(LdapOrganisation.current.puavoActiveService).map { |dn| dn.to_s.downcase }.to_set
    @external_services.reject! { |e| !activated.include?(e[:dn].downcase) }

    @super_owner = super_owner?(current_user.uid)

    respond_to do |format|
      format.html # show.html.erb
    end
  end

  def edit
    unless super_owner?(current_user.uid)
      flash[:alert] = t('flash.you_must_be_an_owner')
      return redirect_to '/'
    end

    # Fill in the current activation states
    activated = Array(LdapOrganisation.current.puavoActiveService).map { |dn| dn.to_s.downcase }.to_set

    @external_services.each do |es|
      es[:active] = activated.include?(es[:dn].downcase)
    end

    # Sort the services alphabetically
    @external_services.sort! { |a, b| a[:name].downcase <=> b[:name].downcase }
  end

  # Unfortunately Rails' magic breaks down here...
  def update
    unless super_owner?(current_user.uid)
      flash[:alert] = t('flash.you_must_be_an_owner')
      return redirect_to '/'
    end

    all_service_dns = ExternalService.all.collect { |e| e.dn.to_s }.to_set

    # Extract the checked services
    form_activated = Set.new

    params.each do |key, value|
      form_activated << key if /^puavoId=\d+,ou=Services,o=Puavo$/i.match(key)
    end

    # Build a new list of active services. Iterate over all known services, so this
    # also removes old deleted services from the list.
    new_activated = Set.new

    all_service_dns.each do |dn|
      new_activated << dn if form_activated.include?(dn)
    end

    begin
      org = LdapOrganisation.current
      org.puavoActiveService = new_activated.to_a
      org.save!
    rescue StandardError => e
      logger.error(e)
      flash[:alert] = t('flash.organisation.external_services_update_failed')
      return redirect_to organisation_external_services_path
    end

    flash[:notice] = t('flash.organisation.external_services_updated')
    redirect_to organisation_external_services_path
  end
end
