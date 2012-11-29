class OrganisationsController < ApplicationController

  # GET /organisation
  def show
    @organisation = LdapOrganisation.current

    respond_to do |format|
      format.html # show.html.erb
      format.json do
        json = JSON.parse @organisation.to_json

        # FIXME: following ldap host is not specified organisation host
        json[:ldap_host] = LdapBase.ensure_configuration["host"]
        json[:kerberos_realm] = @organisation.puavoKerberosRealm
        json[:puavo_domain] = @organisation.puavoDomain
        json[:base] = @organisation.base.to_s

        render :json => json
      end
    end
  end

  # GET /organisation/edit
  def edit
    @organisation = LdapOrganisation.current

    respond_to do |format|
      format.html
    end
  end

  # PUT /organisation
  def update
    @organisation = LdapOrganisation.current

    respond_to do |format|
      if @organisation.update_attributes(params[:ldap_organisation])
        format.html { redirect_to( organisation_path ) }
      else
        format.html { render :action => "edit" }
      end
    end
  end
end
