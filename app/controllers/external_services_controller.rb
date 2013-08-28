class ExternalServicesController < ApplicationController
  def index
    @school = School.find(params["id"]).first
    @external_services = ExternalService.all
    respond_to do |format|
      format.html # index.html.erb
    end
  end
end
