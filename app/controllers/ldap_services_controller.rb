class LdapServicesController < ApplicationController
  # GET /ldap_services
  # GET /ldap_services.xml
  def index
    return if redirected_nonowner_user?

    @ldap_services = LdapService.all
    @system_groups = SystemGroup.all

    respond_to do |format|
      format.html # index.html.erb
      format.xml  { render :xml => @ldap_services }
    end
  end

  # GET /ldap_services/1
  # GET /ldap_services/1.xml
  def show
    return if redirected_nonowner_user?

    @ldap_service = LdapService.find(params[:id])

    respond_to do |format|
      format.html # show.html.erb
      format.xml  { render :xml => @ldap_service }
    end
  end

  # GET /ldap_services/new
  # GET /ldap_services/new.xml
  def new
    return if redirected_nonowner_user?

    @ldap_service = LdapService.new

    @system_groups = SystemGroup.all

    respond_to do |format|
      format.html # new.html.erb
      format.xml  { render :xml => @ldap_service }
    end
  end

  # GET /ldap_services/1/edit
  def edit
    return if redirected_nonowner_user?

    @ldap_service = LdapService.find(params[:id])
    @system_groups = SystemGroup.all
  end

  # POST /ldap_services
  # POST /ldap_services.xml
  def create
    return if redirected_nonowner_user?

    @ldap_service = LdapService.new(ldap_service_params)
    @system_groups = SystemGroup.all

    respond_to do |format|
      if @ldap_service.save
        format.html { redirect_to( ldap_service_path(@ldap_service),
                                   :notice => t('flash.added',
                                                :item => t('activeldap.models.ldap_service') ) ) }
        format.xml  { render :xml => @ldap_service, :status => :created, :location => @ldap_service }
      else
        format.html { render :action => "new" }
        format.xml  { render :xml => @ldap_service.errors, :status => :unprocessable_entity }
      end
    end
  end

  # PUT /ldap_services/1
  # PUT /ldap_services/1.xml
  def update
    return if redirected_nonowner_user?

    @ldap_service = LdapService.find(params[:id])
    @system_groups = SystemGroup.all

    unless params[:ldap_service].has_key?(:group)
      @ldap_service.groups = []
    end

    if params[:ldap_service][:userPassword] && params[:ldap_service][:userPassword].empty?
      params[:ldap_service].delete(:userPassword)
    end

    respond_to do |format|
      if @ldap_service.update_attributes(ldap_service_params)
        format.html { redirect_to( ldap_service_path(@ldap_service),
                                   :notice => t('flash.updated',
                                                :item => t('activeldap.models.ldap_service' ) ) ) }
        format.xml  { head :ok }
      else
        format.html { render :action => "edit" }
        format.xml  { render :xml => @ldap_service.errors, :status => :unprocessable_entity }
      end
    end
  end

  # DELETE /ldap_services/1
  # DELETE /ldap_services/1.xml
  def destroy
    return if redirected_nonowner_user?

    @ldap_service = LdapService.find(params[:id])
    @ldap_service.destroy

    flash[:notice] = t('flash.destroyed', item: t('activeldap.models.ldap_service'))

    respond_to do |format|
      format.html { redirect_to(ldap_services_url) }
      format.xml  { head :ok }
    end
  end

  private
    def ldap_service_params
      return params.require(:ldap_service).permit(:uid, :description, :userPassword, :groups=>[]).to_hash
    end
end
