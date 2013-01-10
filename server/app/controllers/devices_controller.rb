class DevicesController < ApplicationController
  before_filter :find_school

  # GET /devices
  # GET /devices.xml
  def index
    @device = Device.new

    if @school
      @devices = Device.find(:all, :attribute => "puavoSchool", :value => @school.dn)
      @devices = @devices.sort{ |a,b| a.puavoHostname <=> b.puavoHostname }
    elsif request.format == 'application/json' && params[:version] && params[:version] == "v2"
      @devices = Device.search( :scope => :one,
                                :attributes => attributes ).map do |d|
        d.last
      end
      @devices = @devices.map{ |d| Device.build_hash_for_to_json(d) }
    else
      @devices = Device.find(:all)
    end

    if request.format == 'text/html'
      @device_types = Host.types('nothing', current_user)["list"].map{ |k,v| [v['label'], k] }.sort{ |a,b| a.last <=> b.last }
      @device_types = [[I18n.t('devices.index.select_device_label'), '']] + @device_types
    end

    respond_to do |format|
      format.html # index.html.erb
      format.xml  { render :xml => @devices }
      format.json  { render :json => @devices }
    end
  end

  # GET /devices/1
  # GET /devices/1.xml
  # GET /devices/1.json
  def show
    @device = Device.find(params[:id])

    @device.get_certificate(session[:organisation].organisation_key, @authentication.dn, @authentication.password)
    @device.get_ca_certificate(session[:organisation].organisation_key)

    respond_to do |format|
      format.html # show.html.erb
      format.xml  { render :xml => @device }
      format.json  { render :json => @device }
    end
  end

  # GET /:school_id/devices/1/image
  def image
    @device = Device.find(params[:id])

    send_data @device.jpegPhoto, :disposition => 'inline', :type => "image/jpeg"
  end

  # GET /devices/new
  # GET /devices/new.xml
  # GET /devices/new.json
  def new
    @device = Device.new
    @device_type_label = PUAVO_CONFIG['device_types'][params[:device_type]]['label'][I18n.locale.to_s]

    # Try to set default value for hostname
    device = Device.find( :all,
                          :attributes => ["*", "+"],
                          :attribute => 'creatorsName',
                          :value => current_user.dn.to_s).max do |a,b|
      a.puavoId.to_i <=> b.puavoId.to_i
    end

    if device && match_data = device.puavoHostname.to_s.match(/\d+$/)
      number_length = match_data[0].length
      number = match_data[0].to_i + 1
      # Increase the number (end of hostname)
      @default_puavo_hostname = device.puavoHostname.to_s.sub(/\d+$/, ("%0#{number_length}d" % number))
    else
      @default_puavo_hostname = ""
    end

    @device.objectClass_by_device_type = params[:device_type]
    @device.puavoDeviceType = params[:device_type]

    respond_to do |format|
      format.html # new.html.erb
      format.xml  { render :xml => @device }
      format.json
    end
  end

  # GET /devices/1/edit
  def edit
    @device = Device.find(params[:id])
    @device.get_certificate(session[:organisation].organisation_key, @authentication.dn, @authentication.password)
  end

  # POST /devices
  # POST /devices.xml
  # POST /devices.json
  def create
    device_objectClass = params[:device][:classes]
    params[:device].delete(:classes)
    handle_date_multiparameter_attribute(params[:device], :puavoPurchaseDate)
    handle_date_multiparameter_attribute(params[:device], :puavoWarrantyEndDate)
    @device = Device.new( { :objectClass => device_objectClass }.merge( params[:device] ))
    @device.puavoSchool = @school.dn

    if @device.valid?
      unless @device.host_certificate_request.nil?
        @device.sign_certificate(session[:organisation].organisation_key, @authentication.dn, @authentication.password)
        @device.get_ca_certificate(session[:organisation].organisation_key)
      end
    end

    respond_to do |format|
      if @device.save
        format.html { redirect_to(device_path(@school, @device), :notice => 'Device was successfully created.') }
        format.xml  { render :xml => @device, :status => :created, :location => device_path(@school, @device) }
        format.json  { render :json => @device, :status => :created, :location => device_path(@school, @device) }
      else
        format.html { render :action => "new" }
        format.xml  { render :xml => @device.errors, :status => :unprocessable_entity }
        format.json  { render :json => @device.errors, :status => :unprocessable_entity }
      end
    end
  end

  # PUT /devices/1
  # PUT /devices/1.xml
  def update
    @device = Device.find(params[:id])

    handle_date_multiparameter_attribute(params[:device], :puavoPurchaseDate)
    handle_date_multiparameter_attribute(params[:device], :puavoWarrantyEndDate)

    respond_to do |format|
      if @device.update_attributes(params[:device])
        format.html { redirect_to(device_path(@school, @device), :notice => 'Device was successfully updated.') }
        format.xml  { head :ok }
      else
        format.html { render :action => "edit" }
        format.xml  { render :xml => @device.errors, :status => :unprocessable_entity }
      end
    end
  end

  # DELETE /devices/1
  # DELETE /devices/1.xml
  def destroy
    @device = Device.find(params[:id])
    # FIXME, revoke certificate only if device's include certificate
    @device.revoke_certificate(session[:organisation].organisation_key, @authentication.dn, @authentication.password)
    @device.destroy

    respond_to do |format|
      format.html { redirect_to(devices_url) }
      format.xml  { head :ok }
    end
  end

  # DELETE /devices/1
  def revoke_certificate
    @device = Device.find(params[:id])
    # FIXME, revoke certificate only if device's include certificate
    @device.revoke_certificate(session[:organisation].organisation_key, @authentication.dn, @authentication.password)

    # If certificate revoked we have to also disabled device's userPassword
    @server.userPassword = nil

    respond_to do |format|
      format.html { redirect_to(device_path(@school, @device), :notice => 'Device was successfully set to install mode.') }
    end
  end

  # GET /:school_id/devices/:id/select_school
  def select_school
    @device = Device.find(params[:id])
    @schools = School.all.select{ |s| s.id != @school.id }

    respond_to do |format|
      format.html { }
    end
  end

  # POST /:school_id/devices/:id/change_school
  def change_school
    @device = Device.find(params[:id])
    @school = School.find(params[:new_school])

    @device.puavoSchool = @school.dn.to_s
    @device.save!

    respond_to do |format|
      format.html{ redirect_to(device_path(@school, @device), :notice => t('flash.devices.school_changed') ) }
    end
  end

  private

  def find_school
    if params[:school_id]
      @school = School.find(params[:school_id])
    end
  end

  def attributes
    [ "description",
      "ipHostNumber",
      "jpegPhoto",
      "macAddress",
      "puavoDefaultPrinter",
      "puavoDeviceAutoPowerOffMode",
      "puavoDeviceBootMode",
      "puavoDeviceManufacturer",
      "puavoDeviceModel",
      "puavoLatitude",
      "puavoLocationName",
      "puavoLongitude",
      "puavoPurchaseDate",
      "puavoPurchaseLocation",
      "puavoPurchaseURL",
      "puavoSupportContract",
      "puavoTag",
      "puavoWarrantyEndDate",
      "serialNumber",
      "puavoSchool",
      "puavoHostname" ]
  end
end
