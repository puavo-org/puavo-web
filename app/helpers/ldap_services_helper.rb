module LdapServicesHelper

  def ldap_service_group_checked?(ldap_service, group)
    if ldap_service.groups.include?(group) ||
        ( params[:ldap_service] &&
          params[:ldap_service][:groups] &&
          params[:ldap_service][:groups].include?(group.cn) )
      ' checked="checked"'
    else
      ""
    end
  end
end
