class ExternalServicesController < ApplicationController
  # GET /external_services
  # GET /external_services.xml
  def index
    @external_services = ExternalService.all

    respond_to do |format|
      format.html # index.html.erb
      format.xml  { render :xml => @external_services }
    end
  end

  # GET /external_services/1
  # GET /external_services/1.xml
  def show
    @external_service = ExternalService.find(params[:id])

    respond_to do |format|
      format.html # show.html.erb
      format.xml  { render :xml => @external_service }
    end
  end

  # GET /external_services/new
  # GET /external_services/new.xml
  def new
    @external_service = ExternalService.new
    
    @system_groups = SystemGroup.all

    respond_to do |format|
      format.html # new.html.erb
      format.xml  { render :xml => @external_service }
    end
  end

  # GET /external_services/1/edit
  def edit
    @external_service = ExternalService.find(params[:id])
    @system_groups = SystemGroup.all
  end

  # POST /external_services
  # POST /external_services.xml
  def create
    @external_service = ExternalService.new(params[:external_service])

    respond_to do |format|
      if @external_service.save
        format.html { redirect_to( @external_service,
                                   :notice => t('flash.added',
                                                :item => t('activeldap.models.external_service') ) ) }
        format.xml  { render :xml => @external_service, :status => :created, :location => @external_service }
      else
        format.html { render :action => "new" }
        format.xml  { render :xml => @external_service.errors, :status => :unprocessable_entity }
      end
    end
  end

  # PUT /external_services/1
  # PUT /external_services/1.xml
  def update
    @external_service = ExternalService.find(params[:id])
    @system_groups = SystemGroup.all

    unless params[:external_service].has_key?(:group)
      @external_service.groups = []
    end

    if params[:external_service][:userPassword] && params[:external_service][:userPassword].empty?
      params[:external_service].delete(:userPassword)
    end

    respond_to do |format|
      if @external_service.update_attributes(params[:external_service])
        format.html { redirect_to( @external_service,
                                   :notice => t('flash.updated',
                                                :item => t('activeldap.models.external_service' ) ) ) }
        format.xml  { head :ok }
      else
        format.html { render :action => "edit" }
        format.xml  { render :xml => @external_service.errors, :status => :unprocessable_entity }
      end
    end
  end

  # DELETE /external_services/1
  # DELETE /external_services/1.xml
  def destroy
    @external_service = ExternalService.find(params[:id])
    @external_service.destroy

    respond_to do |format|
      format.html { redirect_to(external_services_url) }
      format.xml  { head :ok }
    end
  end
end
