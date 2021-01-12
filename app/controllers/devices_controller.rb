require "devices_helper"

class DevicesController < ApplicationController
  include Puavo::MassOperations

  before_action :find_school

  # GET /devices
  # GET /devices.xml
  def index
    if test_environment? || ['application/json', 'application/xml'].include?(request.format)
      old_legacy_devices_index
    else
      new_cool_devices_index
    end
  end

  # Old "legacy" index used during tests
  def old_legacy_devices_index
    @device = Device.new

    if @school
      @devices = Device.find(:all, :attribute => "puavoSchool", :value => @school.dn)
      @devices.sort!{ |a, b| a.puavoHostname.downcase <=> b.puavoHostname.downcase }
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

  # New AJAX-based index for non-test environments
  def new_cool_devices_index
    @device = Device.new

    # Get a list of schools for the mass tool. I wanted to do this with AJAX
    # calls, getting the list from puavo-rest with the new V4 API, but fetch()
    # and CORS and other domains just won't cooperate...
    @school_list = School.search_as_utf8(:filter => '', :attributes => ['displayName', 'cn']).collect do |s|
        [s[0], s[1]['displayName'][0], s[1]['cn'][0]]
    end.sort do |a, b|
        a[1].downcase <=> b[1].downcase
    end

    if request.format == 'text/html'
      # list of new device types
      @device_types = Host.types('nothing', current_user)["list"].map{ |k,v| [v['label'], k] }.sort{ |a,b| a.last <=> b.last }
      @device_types = [[I18n.t('devices.index.select_device_label'), '']] + @device_types
    end

    respond_to do |format|
      format.html # index.html.erb
    end
  end

  def get_school_devices_list
    @raw = DevicesHelper.get_devices_in_school(@school.dn)

    # convert the raw data into something we can easily parse in JavaScript
    @devices = []

    @raw.each do |dn, dev|
      data = {}

      # common data for all devices
      data.merge!(DevicesHelper.build_common_device_properties(dev))

      # hardware info
      if dev['puavoDeviceHWInfo']
        data.merge!(DevicesHelper.extract_hardware_info(dev['puavoDeviceHWInfo']))
      end

      # link "template" for view/edit/delete hyperlinks
      data.merge!({
        link: device_path(@school, dev['puavoId'][0]),
      })

      # device primary user
      if data[:user]
        u = User.find(data[:user])

        if u
          data[:user] = {
            link: user_path(@school, u),
            title: "#{u[0].uid} (#{u[0].givenName} #{u[0].sn})"
          }
        else
          data.delete(:user)
        end
      end

      data.delete_if{ |k, v| v.nil? }
      @devices << data
    end

    render :json => @devices
  end

  # ------------------------------------------------------------------------------------------------
  # ------------------------------------------------------------------------------------------------

  # Mass operation: delete device
  def mass_op_device_delete
    begin
      device_id = params[:device][:id]
    rescue
      puts "mass_op_device_delete(): missing required params in the request:"
      puts params.inspect
      return status_failed_msg('mass_op_device_delete(): missing params')
    end

    ok = false

    begin
      device = Device.find(device_id)
      device.delete
      ok = true
    rescue StandardError => e
      return status_failed_msg(e)
    end

    if ok
      return status_ok()
    else
      return status_failed_msg('unknown_error')
    end
  end

  # Mass operation: set arbitrary field value
  def mass_op_device_set_field
    begin
      device_id = params[:device][:id]
      field = params[:device][:field]
      value = params[:device][:value]
    rescue
      puts "mass_op_device_set_field(): missing required params in the request:"
      puts params.inspect
      return status_failed_msg('mass_op_device_set_field(): missing params')
    end

    ok = false

    begin
      device = Device.find(device_id)
      changed = false   # save changes only if something actually does change

      # argh, there must be a better way to do this
      case field
        when 'image'
          if device.puavoDeviceImage != value
            device.puavoDeviceImage = value
            changed = true
          end

        when 'kernelargs'
          if device.puavoDeviceKernelArguments != value
            device.puavoDeviceKernelArguments = value
            changed = true
          end

        when 'kernelversion'
          if device.puavoDeviceKernelVersion != value
            device.puavoDeviceKernelVersion = value
            changed = true
          end

        when 'puavoconf'
          if device.puavoConf != value
            device.puavoConf = value
            changed = true
          end

        when 'tags'
          if device.puavoTag != value
            device.puavoTag = value
            changed = true
          end

        when 'manufacturer'
          if device.puavoDeviceManufacturer != value
            device.puavoDeviceManufacturer = value
            changed = true
          end

        when 'model'
          if device.puavoDeviceModel != value
            device.puavoDeviceModel = value
            changed = true
          end

        when 'serial'
          if device.serialNumber != value
            device.serialNumber = value
            changed = true
          end
      end

      if changed
        device.save!
      end

      # don't raise errors when nothing happens
      ok = true
    rescue StandardError => e
      return status_failed_msg(e)
    end

    if ok
      return status_ok()
    else
      return status_failed_msg('unknown_error')
    end
  end

  # Mass operation: puavoconf editor
  def mass_op_device_edit_puavoconf
    begin
      device_id = params[:device][:id]
      key = params[:device][:key]
      value = params[:device][:value]
      type = params[:device][:type]
      action = params[:device][:action]
    rescue
      puts "mass_op_device_edit_puavoconf(): missing required params in the request:"
      puts params.inspect
      return status_failed_msg('mass_op_device_edit_puavoconf(): missing params')
    end

    ok = false

    if type == 'string'
      value = value.to_s
    elsif type == 'int'
      value = value.to_i(10)
    elsif type == 'bool'
      if value == 'true'
        value = true
      elsif value == 'false'
        value = false
      else
        value = value.to_i ? true : false
      end
    end

    begin
      device = Device.find(device_id)
      changed = false   # save changes only if something actually does change

      conf = device.puavoConf ? JSON.parse(device.puavoConf) : {}

      if action == 0
        # ADD/CHANGE
        if conf.include?(key)
          if conf[key] != value
            conf[key] = value
            changed = true
          end
        else
          conf[key] = value
          changed = true
        end
      else
        # REMOVE
        if conf.include?(key)
          conf.delete(key)
          changed = true
        end
      end

      if changed
        if conf.empty?
          # empty hash serializes as "{}" in JSON, but that's not what we want
          device.puavoConf = nil
        else
          device.puavoConf = conf.to_json
        end

        device.save!
      end

      # don't raise errors when nothing happens
      ok = true
    rescue StandardError => e
      return status_failed_msg(e)
    end

    if ok
      return status_ok()
    else
      return status_failed_msg('unknown_error')
    end
  end

  # Mass operation: change school
  def mass_op_device_change_school
    begin
      device_id = params[:device][:id]
      school_dn = params[:device][:school_dn]
    rescue
      puts "mass_op_device_change_school(): missing required params in the request:"
      puts params.inspect
      return status_failed_msg('mass_op_device_delete(): missing params')
    end

    ok = false

    begin
      device = Device.find(device_id)

      if device.puavoSchool.to_s != school_dn
        device.puavoSchool = school_dn
        device.save!
      end

      ok = true
    rescue StandardError => e
      return status_failed_msg(e)
    end

    if ok
      return status_ok()
    else
      return status_failed_msg('unknown_error')
    end
  end

  # Mass operation: edit purchase information
  def mass_op_device_purchase_info
    begin
      device_id = params[:device][:id]
      purchase_params = params[:device][:purchase_params]
    rescue
      puts "mass_op_device_purchase_info(): missing required params in the request:"
      puts params.inspect
      return status_failed_msg('mass_op_device_purchase_info(): missing params')
    end

    ok = false

    begin
      device = Device.find(device_id)
      changed = false

      if purchase_params.include?('purchase_date')
        old_date = device.puavoPurchaseDate ? device.puavoPurchaseDate.strftime('%Y-%m-%d') : nil
        new_date = purchase_params['purchase_date']

        if old_date != new_date
          device.puavoPurchaseDate = new_date ? Time.strptime("#{new_date} 00:00:00 UTC", '%Y-%m-%d %H:%M:%S %Z') : nil
          changed = true
        end
      end

      if purchase_params.include?('purchase_warranty')
        old_date = device.puavoWarrantyEndDate ? device.puavoWarrantyEndDate.strftime('%Y-%m-%d') : nil
        new_date = purchase_params['purchase_warranty']

        if old_date != new_date
          device.puavoWarrantyEndDate = new_date ? Time.strptime("#{new_date} 00:00:00 UTC", '%Y-%m-%d %H:%M:%S %Z') : nil
          changed = true
        end
      end

      if purchase_params.include?('purchase_loc') && device.puavoPurchaseLocation != purchase_params['purchase_loc']
        device.puavoPurchaseLocation = purchase_params['purchase_loc']
        changed = true
      end

      if purchase_params.include?('purchase_url') && device.puavoPurchaseURL != purchase_params['purchase_url']
        device.puavoPurchaseURL = purchase_params['purchase_url']
        changed = true
      end

      if purchase_params.include?('purchase_support') && device.puavoSupportContract != purchase_params['purchase_support']
        device.puavoSupportContract = purchase_params['purchase_support']
        changed = true
      end

      if changed
        device.save!
      end

      ok = true
    rescue StandardError => e
      return status_failed_msg(e)
    end

    if ok
      return status_ok()
    else
      return status_failed_msg('unknown_error')
    end
  end

  # ------------------------------------------------------------------------------------------------
  # ------------------------------------------------------------------------------------------------

  # GET /devices/1
  # GET /devices/1.xml
  # GET /devices/1.json
  def show
    @device = get_device(params[:id])
    return if @device.nil?

    # get the creation and modification timestamps from LDAP operational attributes
    extra = Device.find(params[:id], :attributes => ['createTimestamp', 'modifyTimestamp'])
    @device['createTimestamp'] = convert_timestamp(extra['createTimestamp'])
    @device['modifyTimestamp'] = convert_timestamp(extra['modifyTimestamp'])

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
    @is_new_device = true

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
    @device = get_device(params[:id])
    return if @device.nil?

    @is_new_device = false

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

    # None of the device types you can create directory using puavo-web allows you to specify
    # the primary user for the device. The only place that can set it is puavo-register.
    # And this is where those calls end up in. This is ugly code, but in a different way.
    primary_user_failed = false

    if dp['puavoDevicePrimaryUser']
      dn = DeviceBase.uid_to_dn(dp['puavoDevicePrimaryUser'])

      if dn
        @device.puavoDevicePrimaryUser = dn
      else
        primary_user_failed = true

        @device.errors.add(:puavoDevicePrimaryUser,
                           I18n.t("activeldap.errors.messages.invalid",
                           :attribute => I18n.t('activeldap.attributes.device.puavoDevicePrimaryUser')))
      end
    end

    if !primary_user_failed && @device.valid?
      unless @device.host_certificate_request.nil?
        @device.sign_certificate(current_organisation.organisation_key, @authentication.dn, @authentication.password)
        @device.get_ca_certificate(current_organisation.organisation_key)
      end
    end

    respond_to do |format|
      if !primary_user_failed && @device.save
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
    @device = get_device(params[:id])
    return if @device.nil?

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

    # This is so ugly code. I'm sorry.
    failed = false

    if dp['puavoDevicePrimaryUser'].nil? || dp['puavoDevicePrimaryUser'].empty?
      # Clear
      dp['puavoDevicePrimaryUser'] = nil
    else
      # Set
      dn = DeviceBase.uid_to_dn(dp['puavoDevicePrimaryUser'])

      if dn
        dp['puavoDevicePrimaryUser'] = dn
      else
        flash[:alert] = t('flash.save_failed')

        # copied/moved from the model validation code
        @device.errors.add(:puavoDevicePrimaryUser,
                           I18n.t("activeldap.errors.messages.invalid",
                           :attribute => I18n.t('activeldap.attributes.device.puavoDevicePrimaryUser')))

        failed = true
      end
    end

    @school_printers = school_printers

    respond_to do |format|
      if !failed && @device.update_attributes(dp)
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
    @device = get_device(params[:id])
    return if @device.nil?

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
    @device = get_device(params[:id])
    return if @device.nil?

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

    # sort the schools, so you can actually find the one you're looking for
    @schools.sort!{ |a, b| a.displayName.downcase <=> b.displayName.downcase }

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
      "puavoConf",
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
      :puavoConf,
      :puavoDeviceStatus,
      :image,
      :puavoDeviceManufacturer,
      :puavoDeviceModel,
      :serialNumber,
      :puavoDevicePrimaryUser,
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
      :puavoDeviceMonitorsXML,
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

    strip_img(p)

    clear_puavoconf(p)

    return p
  end

    def get_device(id)
      begin
        return Device.find(id)
      rescue ActiveLdap::EntryNotFound => e
        flash[:alert] = t('flash.invalid_device_id', :id => id)
        redirect_to devices_path(@school)
        return nil
      end
    end

end
