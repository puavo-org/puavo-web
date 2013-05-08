class MenuController < ApplicationController
  layout 'sessions'
  skip_before_filter :require_puavo_authorization
  skip_before_filter :require_login

  # GET /menu
  def index
    @organisation = Puavo::Organisation.find organisation_key_from_host

    if organisation_services = @organisation.value_by_key("services")
      services = @organisation.value_by_key("services")
    else
      services = @services = Puavo::SERVICES["defaults"]
    end

    @services = Puavo::SERVICES["services"].select{ |s| services.include?(s.keys.first) }
    
    respond_to do |format|
      format.html
    end
  end
end
