class DevicesController < ApplicationController
  before_action :find_school

  # GET /devices
  # GET /devices.xml
  def index
    @device = Device.new

    if @school
      @devices = Device.find(:all, :attribute => "puavoSchool", :value => @school.dn)
      @devices = @devices.sort{ |a,b| a.puavoHostname <=> b.puavoHostname }
    elsif request.format == 'application/json' && params[:version] && params[:version] == "v2"
      @devices = Device.search_as_utf8( :scope => :one,
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

    @device.get_certificate(current_organisation.organisation_key, @authentication.dn, @authentication.password)
    @device.get_ca_certificate(current_organisation.organisation_key)

    if @device.attributes.include?("puavoPreferredServer") && @device.puavoPreferredServer
      if preferred_server = Server.find(@device.puavoPreferredServer)
        @preferred_server_name = preferred_server.puavoHostname
      end
    end

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
    # validate the device type before doing anything else
    if !Puavo::CONFIG["device_types"].has_key?(params[:device_type])
      flash[:error] = t('flash.unknown_device_type')
      redirect_to devices_url
      return
    end

    @device = Device.new
    @device_type_label = Puavo::CONFIG['device_types'][params[:device_type]]['label'][I18n.locale.to_s]

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
    @device.get_certificate(current_organisation.organisation_key, @authentication.dn, @authentication.password)

    @servers = Server.all.map{ |server|  [server.puavoHostname, server.dn.to_s] }

    @school_printers = school_printers

  end

  # POST /devices
  # POST /devices.xml
  # POST /devices.json
  def create
    device_objectClass = params[:device][:classes]
    params[:device].delete(:classes)

    dp = device_params
    handle_date_multiparameter_attribute(dp, "puavoPurchaseDate")
    handle_date_multiparameter_attribute(dp, "puavoWarrantyEndDate")
    dp[:objectClass] = device_objectClass
    @device = Device.new(dp)
    @device.puavoSchool = @school.dn

    # @device_type_label is used in the form title. It is set correctly on the first time
    # the form is opened, but if the (new) device cannot be saved, the title gets lost.
    # Re-set it and do some rudimentary error checking.
    begin
      @device_type_label = Puavo::CONFIG['device_types'][params[:device][:puavoDeviceType]] \
        ['label'][I18n.locale.to_s]
    rescue
      # I'm pretty sure this cannot happen, but...
      @device_type_label = "???"
    end

    if @device.valid?
      unless @device.host_certificate_request.nil?
        @device.sign_certificate(current_organisation.organisation_key, @authentication.dn, @authentication.password)
        @device.get_ca_certificate(current_organisation.organisation_key)
      end
    end

    respond_to do |format|
      if @device.save
        format.html { redirect_to(device_path(@school, @device), :notice => t('flash.device_created')) }
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

    (params["printers"] || {}).each do |printer_dn, bool|
      if bool == "true"
        @device.add_printer(printer_dn)
      else
        @device.remove_printer(printer_dn)
      end
    end
    @device.save!

    dp = device_params
    handle_date_multiparameter_attribute(dp, "puavoPurchaseDate")
    handle_date_multiparameter_attribute(dp, "puavoWarrantyEndDate")

    @school_printers = school_printers

    respond_to do |format|
      if @device.update_attributes(dp)
        format.html { redirect_to(device_path(@school, @device), :notice => t('flash.device_updated')) }
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
    @device.revoke_certificate(current_organisation.organisation_key, @authentication.dn, @authentication.password)
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
    @device.revoke_certificate(current_organisation.organisation_key, @authentication.dn, @authentication.password)

    # If certificate revoked we have to also disabled device's userPassword
    @device.userPassword = nil

    respond_to do |format|
      format.html { redirect_to(device_path(@school, @device), :notice => t('flash.set_install_mode')) }
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
      begin
        @school = School.find(params[:school_id])
      rescue ActiveLdap::EntryNotFound
        flash[:error] = t('flash.invalid_school_id')
        redirect_to "/"
      end
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

  def school_printers
    school_printers = []
    @school.printers.each do |printer|
      has_printer = @device.has_printer?(printer)
      input_disabled = false
      if @school.has_printer?(printer)
        input_disabled = true
        has_printer = true
      end
      school_printers.push({ :has_printer => has_printer,
                             :input_disabled => input_disabled,
                             :object => printer })
    end
    return school_printers
  end

  def device_params
    p = params.require(:device).permit(
      :devicetype,                # these are...
      :school,                    # ...used during...
      :host_certificate_request,  # ...device registration
      :puavoDeviceType,
      :puavoHostname,
      :puavoTag,
      :puavoDeviceStatus,
      :image,
      :puavoDeviceManufacturer,
      :puavoDeviceModel,
      :serialNumber,
      :primary_user_uid,
      :puavoDeviceBootMode,
      :puavoDeviceDefaultAudioSource,
      :puavoDeviceDefaultAudioSink,
      :puavoAllowGuest,
      :puavoPersonalDevice,
      :puavoAutomaticImageUpdates,
      :puavoPersonallyAdministered,
      :ipHostNumber,
      :description,
      :puavoDeviceAutoPowerOffMode,
      :puavoDeviceOnHour,
      :puavoDeviceOffHour,
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
      :puavoDeviceBootImage,
      :puavoPreferredServer,
      :puavoDeviceKernelVersion,
      :puavoDeviceKernelArguments,
      :puavoPrinterDeviceURI,
      :puavoPrinterPPD,
      :puavoDefaultPrinter,
      :printerDescription,
      :printerURI,
      :printerLocation,
      :printerMakeAndModel,
      :puavoPrinterCartridge,
      :macAddress=>[],
      :puavoDeviceXrandr=>[],
      :puavoImageSeriesSourceURL=>[],
      :fs=>[],
      :path=>[],
      :mountpoint=>[],
      :options=>[]).to_hash

    # deduplicate arrays, as LDAP really does not like duplicate entries...
    p["puavoTag"] = p["puavoTag"].split.uniq.join(' ') if p.key?("puavoTag")
    p["macAddress"].uniq! if p.key?("macAddress")
    p["puavoDeviceXrandr"].uniq! if p.key?("puavoDeviceXrandr")
    p["puavoImageSeriesSourceURL"].uniq! if p.key?("puavoImageSeriesSourceURL")

    return p
  end

end
