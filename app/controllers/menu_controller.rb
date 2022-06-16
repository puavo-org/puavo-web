class MenuController < ApplicationController
  include Puavo::LoginCustomisations

  skip_before_action :require_puavo_authorization
  skip_before_action :require_login

  # GET /menu
  def index
    @organisation = Puavo::Organisation.find organisation_key_from_host

    # TODO: Figure out why this makes things break in various ways.
    #I18n.locale = @organisation.locale

    @services = @organisation.value_by_key("services") || Puavo::SERVICES["services"]

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
