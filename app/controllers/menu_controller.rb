class MenuController < ApplicationController
  layout 'sessions'
  skip_before_filter :require_puavo_authorization
  skip_before_filter :require_login

  # GET /menu
  def index

    @services = Puavo::SERVICES["services"]

    @organisation = Puavo::Organisation.find organisation_key_from_host

    @services = @organisation.value_by_key("services") || @services

    respond_to do |format|
      format.html
    end
  end
end
