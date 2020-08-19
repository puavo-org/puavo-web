class MenuController < ApplicationController
  include Puavo::LoginCustomisations

  layout 'sessions'
  skip_before_action :require_puavo_authorization
  skip_before_action :require_login

  # GET /menu
  def index

    @services = Puavo::SERVICES["services"]

    @organisation = Puavo::Organisation.find organisation_key_from_host

    @services = @organisation.value_by_key("services") || @services

    @login_content = {
      "prefix" => "/login"
    }

    # Per-customer customisations, if any
    @login_content.merge!(customise_login_screen())

    respond_to do |format|
      format.html
    end
  end
end
