class OrganisationExternalServicesController < ExternalServicesBase

  before_filter do
    @model = LdapOrganisation.current
  end

  def put_path
    organisation_external_services_path
  end

  def is_disabled?(*)
    # Checkboxes cannot be disabled on organisation level form
    false
  end

  def is_checked?(external_service)
    Array(@model.puavoActiveService).include?(external_service.dn)
  end

end
