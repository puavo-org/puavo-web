class DevicesController < ApplicationController
  before_filter :find_school

  # GET /devices
  # GET /devices.xml
  def index
    @devices = Device.find(:all, :attribute => "puavoSchool", :value => @school.dn)
    @devices = @devices.sort{ |a,b| a.puavoHostname <=> b.puavoHostname }

    respond_to do |format|
      format.html # index.html.erb
      format.xml  { render :xml => @devices }
    end
  end

  # GET /devices/1
  # GET /devices/1.xml
  # GET /devices/1.json
  def show
    @device = Device.find(params[:id])

    @device.get_certificate(session[:organisation].organisation_key, session[:dn], session[:password_plaintext])
    @device.get_ca_certificate(session[:organisation].organisation_key)

    respond_to do |format|
      format.html # show.html.erb
      format.xml  { render :xml => @device }
      format.json  { render :json => @device }
    end
  end

  # GET /devices/new
  # GET /devices/new.xml
  # GET /devices/new.json
  def new
    @device = Device.new

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
    @device.get_certificate(session[:organisation].organisation_key, session[:dn], session[:password_plaintext])
  end

  # POST /devices
  # POST /devices.xml
  # POST /devices.json
  def create
    device_objectClass = params[:device][:classes]
    params[:device].delete(:classes)
    @device = Device.new( { :objectClass => device_objectClass }.merge( params[:device] ))

    @device.puavoSchool = @school.dn

    if @device.valid?
      unless @device.host_certificate_request.nil?
        @device.sign_certificate(session[:organisation].organisation_key, session[:dn], session[:password_plaintext])
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
    @device.revoke_certificate(session[:organisation].organisation_key, session[:dn], session[:password_plaintext])
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
    @device.revoke_certificate(session[:organisation].organisation_key, session[:dn], session[:password_plaintext])

    # If certificate revoked we have to also disabled device's userPassword
    @server.userPassword = nil

    respond_to do |format|
      format.html { redirect_to(device_path(@school, @device), :notice => 'Device was successfully set to install mode.') }
    end
  end

  private

  def find_school
    @school = School.find(params[:school_id])
  end
end
