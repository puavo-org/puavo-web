class DevicesController < ApplicationController
  # GET /devices
  # GET /devices.xml
  def index
    @devices = Device.all

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

    respond_to do |format|
      unless params[:device]
        format.html {  render :partial => 'device_role' }
        format.json {  render :partial => 'device_role' }
      else
        @device.add_class(params[:device][:classes])
        format.html # new.html.erb
        format.xml  { render :xml => @device }
        format.json
      end
    end
  end

  # GET /devices/1/edit
  def edit
    @device = Device.find(params[:id])
  end

  # POST /devices
  # POST /devices.xml
  # POST /devices.json
  def create
    @device = Device.new( { :objectClass => 'puavoNetbootDevice' }.merge( params[:device] ))
    @device.puavoSchool = "puavoId=1,ou=Groups,dc=edu,dc=kunta1,dc=fi" # School.first.dn

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
    @device.destroy

    respond_to do |format|
      format.html { redirect_to(devices_url) }
      format.xml  { head :ok }
    end
  end
end
