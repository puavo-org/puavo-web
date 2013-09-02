class Schools::ExternalServicesController < ApplicationController

  def show
    @external_services = ExternalService.all
    respond_to do |format|
      format.html # show.html.erb
    end
  end

  def update
    @school.puavoActiveService = params["puavoActiveService"]
    @school.save!
    flash[:notice] = "Saved!"
    redirect_to :back
  end

end
