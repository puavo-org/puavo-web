module ExternalServicesHelper

  def external_service_group_checked?(external_service, group)
    if external_service.groups.include?(group) ||
        ( params[:external_service] &&
          params[:external_service][:groups] &&
          params[:external_service][:groups].include?(group.cn) )
      ' checked="checked"'
    else
      ""
    end
  end
end
