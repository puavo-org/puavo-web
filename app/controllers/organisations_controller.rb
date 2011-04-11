class OrganisationsController < ApplicationController

  # GET /organisation
  def show
    @organisation = LdapOrganisation.current

    respond_to do |format|
      format.html # show.html.erb
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
