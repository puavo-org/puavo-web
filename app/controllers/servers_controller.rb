class ServersController < ApplicationController
  # GET /servers
  # GET /servers.xml
  def index
    @servers = Server.all
    @servers = @servers.sort{ |a,b| a.puavoHostname <=> b.puavoHostname }

    respond_to do |format|
      if current_user.organisation_owner?
        format.html # index.html.erb
        format.xml  { render :xml => @servers }
      else
        @schools = School.all_with_permissions
        if @schools.count > 1 && Puavo::CONFIG["school"]
          format.html { redirect_to( "/users/schools" ) }
        else
          format.html { redirect_to( devices_path(@schools.first) ) }
        end
      end
    end
  end

  # GET /servers/1
  # GET /servers/1.xml
  def show
    @server = Server.find(params[:id])
    @server.get_certificate(current_organisation.organisation_key, @authentication.dn, @authentication.password)
    @server.get_ca_certificate(current_organisation.organisation_key)

    respond_to do |format|
      format.html # show.html.erb
      format.xml  { render :xml => @server }
    end
  end

  # GET /servers/1/image
  def image
    @server = Server.find(params[:id])

    send_data @server.jpegPhoto, :disposition => 'inline', :type => "image/jpeg"
  end

  # GET /servers/new
  # GET /servers/new.xml
  def new
    @server = Server.new

    respond_to do |format|
      format.html # new.html.erb
      format.xml  { render :xml => @server }
      format.json
    end
  end

  # GET /servers/1/edit
  def edit
    @server = Server.find(params[:id])
    @schools = School.all
    @server.get_certificate(current_organisation.organisation_key, @authentication.dn, @authentication.password)
  end

  # POST /servers
  # POST /servers.xml
  def create
    sp = server_params

    handle_date_multiparameter_attribute(sp, :puavoPurchaseDate)
    handle_date_multiparameter_attribute(sp, :puavoWarrantyEndDate)

    @server = Server.new(sp)

    if @server.valid?
      unless @server.host_certificate_request.nil?
        @server.sign_certificate(current_organisation.organisation_key, @authentication.dn, @authentication.password)
        @server.get_ca_certificate(current_organisation.organisation_key)
      end
    end

    respond_to do |format|
      if @server.save
        flash[:notice] = t('flash.server_created')
        format.html { redirect_to(@server) }
        format.xml  { render :xml => @server, :status => :created, :location => @server }
        format.json  { render :json => @server, :status => :created, :location => @server }
      else
        format.html { render :action => "new" }
        format.xml  { render :xml => @server.errors, :status => :unprocessable_entity }
        format.json  { render :json => @server.errors, :status => :unprocessable_entity }
      end
    end
  end

  # PUT /servers/1
  # PUT /servers/1.xml
  def update
    @server = Server.find(params[:id])
    @schools = School.all

    sp = server_params

    handle_date_multiparameter_attribute(sp, :puavoPurchaseDate)
    handle_date_multiparameter_attribute(sp, :puavoWarrantyEndDate)

    @server.attributes = sp

    # Just updating attributes is not enough for removing #puavoSchool value
    # when no checkboxes are checked because params[:server][:puavoSchool] will
    # be nil and it will be just ignored by attributes update
    @server.puavoSchool = sp["puavoSchool"]

    respond_to do |format|
      if @server.save
        flash[:notice] = t('flash.server_updated')
        format.html { redirect_to(@server) }
        format.xml  { head :ok }
      else
        format.html { render :action => "edit" }
        format.xml  { render :xml => @server.errors, :status => :unprocessable_entity }
      end
    end
  end

  # DELETE /servers/1
  # DELETE /servers/1.xml
  def destroy
    @server = Server.find(params[:id])
    # FIXME, revoke certificate only if device's include certificate
    @server.revoke_certificate(current_organisation.organisation_key, @authentication.dn, @authentication.password)
    @server.destroy

    # FIXME: remove printers of this server!

    respond_to do |format|
      format.html { redirect_to(servers_url) }
      format.xml  { head :ok }
    end
  end

  # DELETE /servers/1
  def revoke_certificate
    @server = Server.find(params[:id])
    # FIXME, revoke certificate only if server's include certificate
    @server.revoke_certificate(current_organisation.organisation_key, @authentication.dn, @authentication.password)

    # If certificate revoked we have to also disabled device's userPassword
    @server.userPassword = nil

    respond_to do |format|
      format.html { redirect_to(server_path(@server), :notice => t('flash.set_install_mode_server')) }
    end
  end

  private
    def server_params
      server = params.require(:server).permit(
        :puavoHostname,
        :puavoTag,
        :puavoDeviceStatus,
        :image,
        :puavoDeviceManufacturer,
        :puavoDeviceModel,
        :serialNumber,
        :primary_user_uid,
        :puavoPrinterDeviceURI,
        :puavoPrinterPPD,
        :puavoDefaultPrinter,
        :puavoDeviceDefaultAudioSource,
        :puavoDeviceDefaultAudioSink,
        :description,
        :puavoPurchaseDate,
        :puavoWarrantyEndDate,
        :puavoPurchaseLocation,
        :puavoPurchaseURL,
        :puavoSupportContract,
        :puavoLocationName,
        :puavoLatitude,
        :puavoLongitude,
        :puavoDeviceXserver,
        :puavoDeviceXrandrDisable,
        :puavoDeviceResolution,
        :puavoDeviceHorzSync,
        :puavoDeviceVertRefresh,
        :puavoDeviceImage,
        :puavoDeviceKernelVersion,
        :puavoDeviceKernelArguments,
        :macAddress=>[],
        :puavoImageSeriesSourceURL=>[],
        :fs=>[],
        :path=>[],
        :mountpoint=>[],
        :options=>[],
        :puavoExport=>[],
        :puavoSchool=>[]
      ).to_hash

      server["puavoTag"] = server["puavoTag"].split.uniq.join(' ') if server.key?("puavoTag")
      server["puavoExport"].uniq! if server.key?("puavoExport")
      server["macAddress"].uniq! if server.key?("macAddress")

      # For some reason, server parameters have been split into
      # multiple hashes and each one must be permitted separately.
      # Perhaps there is a better way to do this?

      device = params.require(:device).permit(
        :puavoDeviceXrandr=>[]
      ).to_hash

      return server.merge(device)

    end

end
