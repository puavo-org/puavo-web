class ExternalServicesBase < ApplicationController

  helper_method :put_path, :is_disabled?, :is_checked?


  def show
    @external_services = ExternalService.all.select do |s|
      !s.puavoServiceTrusted
    end

    @external_services.sort!{|a, b| a.cn.downcase <=> b.cn.downcase }

    respond_to do |format|
      format.html # show.html.erb
    end
  end

  def update
    logger.info "#{ current_user.displayName } (#{ current_user.dn }) is setting #{ @model.cn} (#{ @model.dn }) external services to #{ params["puavoActiveService"].inspect }"

    @model.puavoActiveService = params["puavoActiveService"]
    @model.save!
    flash[:notice] = t('flash.external_services_saved')
    redirect_back fallback_location: organisation_external_services_path
  end


end
