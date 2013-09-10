class ExternalServicesBase < ApplicationController

  helper_method :put_path, :is_disabled?, :is_checked?


  def show
    @external_services = ExternalService.all.select do |s|
      !s.puavoServiceTrusted
    end

    respond_to do |format|
      format.html # show.html.erb
    end
  end

  def update
    logger.info "#{ current_user.displayName } (#{ current_user.dn }) is setting #{ @model.cn} (#{ @model.dn }) external services to #{ params["puavoActiveService"].inspect }"

    @model.puavoActiveService = params["puavoActiveService"]
    @model.save!
    flash[:notice] = "Saved!"
    redirect_to :back
  end


end
