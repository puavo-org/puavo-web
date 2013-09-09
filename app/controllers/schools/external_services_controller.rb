class Schools::ExternalServicesController < ExternalServicesBase


  before_filter do
    @model = @school
  end

  def put_path
    schools_external_services_path
  end

  def is_disabled?(external_service)
    services = Array(LdapOrganisation.current.puavoActiveService)
    return services.include?(external_service.dn)
  end

  def is_checked?(external_service)
    return (
      is_disabled?(external_service) ||
      Array(@model.puavoActiveService).include?(external_service.dn)
    )
  end

end
