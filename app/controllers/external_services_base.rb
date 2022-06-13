class ExternalServicesBase < ApplicationController

  helper_method :put_path, :is_disabled?, :is_checked?


  def show
    @external_services = ExternalService.all.select do |s|
      !s.puavoServiceTrusted
    end

    @extra = {}

    @external_services.each do |e|
      raw = ExternalService.find(e.dn, :attributes => ['createTimestamp'])

      @extra[e.dn.to_s] = {
        created: raw.createTimestamp,
      }
    end

    @external_services.sort!{|a, b| a.cn.downcase <=> b.cn.downcase }

    @is_owner = is_owner?

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
