require 'devices_helper'
require 'set'

require_relative '../../rest/lib/inventory.rb'

class DevicesController < ApplicationController
  include Puavo::Inventory
  include Puavo::PuavomenuEditor

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

    @is_owner = is_owner?
    @permit_device_creation = @is_owner || current_user.has_admin_permission?(:create_devices)
    @permit_device_deletion = @is_owner || current_user.has_admin_permission?(:delete_devices)
    @permit_device_mass_deletion = false    # JavaScript only, and the legacy index does not have JS

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
    @is_owner = is_owner?

    @permit_device_creation = @is_owner || current_user.has_admin_permission?(:create_devices)
    @permit_device_deletion = @is_owner || current_user.has_admin_permission?(:delete_devices)
    @permit_device_mass_deletion = @is_owner || (@permit_device_deletion && current_user.has_admin_permission?(:mass_delete_devices))
    @permit_device_reset = @is_owner || current_user.has_admin_permission?(:reset_devices)
    @permit_device_mass_reset = @is_owner || current_user.has_admin_permission?(:mass_reset_devices)

    @device = Device.new

    if is_owner?
      @school_list = DevicesHelper.device_school_change_list(true, current_user, @school.dn.to_s)
    else
      @school_list = DevicesHelper.device_school_change_list(false, current_user, @school.dn.to_s)
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

  # AJAX call
  def get_school_devices_list
    # Get a raw list of devices in this school
    raw = Device.search_as_utf8(:filter => "(puavoSchool=#{@school.dn})",
                                :scope => :one,
                                :attributes => DevicesHelper.get_device_attributes())

    # Known image release names
    releases = get_releases()

    # Convert the raw data into something we can easily parse in JavaScript
    school_id = @school.id.to_i
    devices = []

    raw.each do |dn, dev|
      # Common attributes
      device = DevicesHelper.convert_raw_device(dev, releases)

      # Special attributes
      device[:link] = "/devices/#{school_id}/devices/#{device[:id]}"
      device[:school_id] = school_id

      # Figure out the primary user
      if device[:user]
        device[:user] = DevicesHelper.format_device_primary_user(device[:user], school_id)
      end

      devices << device
    end

    render :json => devices
  end

  # GET /devices/1
  # GET /devices/1.xml
  # GET /devices/1.json
  def show
    @device = get_device(params[:id])
    return if @device.nil?

    # get the creation, modification and last authentication timestamps from
    # LDAP operational attributes
    extra = Device.find(params[:id], :attributes => ['authTimestamp', 'createTimestamp', 'modifyTimestamp'])
    @device['authTimestamp']   = convert_timestamp_pick_date(extra['authTimestamp']) if extra['authTimestamp']
    @device['createTimestamp'] = convert_timestamp(extra['createTimestamp'])
    @device['modifyTimestamp'] = convert_timestamp(extra['modifyTimestamp'])

    @device.get_certificate(current_organisation.organisation_key, @authentication.dn, @authentication.password)
    @device.get_ca_certificate(current_organisation.organisation_key)

    @permit_device_deletion = is_owner? || current_user.has_admin_permission?(:delete_devices)
    @permit_device_reset = is_owner? || current_user.has_admin_permission?(:reset_devices)

    @releases = get_releases

    @reset = nil

    if @device.puavoDeviceReset
      @reset = JSON.parse(@device.puavoDeviceReset) rescue nil

      unless @reset.kind_of?(Hash) && @reset['request-time'] && !@reset['request-fulfilled']
        @reset = nil
      else
        @reset['request-time'] = DateTime.parse(@reset['request-time']).strftime('%Y-%m-%d %H:%M:%S')

        if @reset['request-fulfilled']
          @reset['request-fulfilled'] = DateTime.parse(@reset['request-time']).strftime('%Y-%m-%d %H:%M:%S')
        end
      end
    end

    # operation: fast-reset, reset
    # mode: ask_pin

    make_puavomenu_preview(@device.puavoMenuData)

    @fqdn = "#{@device.puavoHostname}.#{LdapOrganisation.current.puavoDomain}"

    @full_puavoconf = list_all_puavoconf_values(LdapOrganisation.current.puavoConf, @school.puavoConf, @device.puavoConf)

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

  # GET /:school_id/devices/:id/raw_hardware_info
  def raw_hardware_info
    device = Device.find(params[:id])
    data = {}

    begin
      data = JSON.parse(device.puavoDeviceHWInfo)
    rescue => e
    end

    send_data data.to_json,
              type: :json,
              disposition: "attachment",
              filename: "#{current_organisation.organisation_key}-#{device.cn}.json"
  end

  # GET /devices/new
  # GET /devices/new.xml
  # GET /devices/new.json
  def new
    unless is_owner? || current_user.has_admin_permission?(:create_devices)
      flash[:alert] = t('flash.you_must_be_an_owner')
      redirect_to devices_url
      return
    end

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
    unless is_owner? || current_user.has_admin_permission?(:create_devices)
      flash[:alert] = t('flash.you_must_be_an_owner')
      redirect_to devices_url
      return
    end

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
    primary_user_ok = true

    if !dp['puavoDevicePrimaryUser'].nil? && !dp['puavoDevicePrimaryUser'].strip.empty?
      dn = DeviceBase.uid_to_dn(dp['puavoDevicePrimaryUser'].strip)

      if dn
        @device.puavoDevicePrimaryUser = dn
      else
        primary_user_ok = false

        @device.errors.add(:puavoDevicePrimaryUser,
                           I18n.t("activeldap.errors.messages.invalid",
                           :attribute => I18n.t('activeldap.attributes.device.puavoDevicePrimaryUser')))
      end
    end

    if primary_user_ok && @device.valid?
      unless @device.host_certificate_request.nil?
        @device.sign_certificate(current_organisation.organisation_key, @authentication.dn, @authentication.password)
        @device.get_ca_certificate(current_organisation.organisation_key)
      end
    end

    respond_to do |format|
      if primary_user_ok && @device.save
        if Puavo::CONFIG['inventory_management']
          # Notify the external inventory management
          Puavo::Inventory::device_created(logger, Puavo::CONFIG['inventory_management'], @device, current_organisation.organisation_key)
        end
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
        if Puavo::CONFIG['inventory_management']
          # Notify the external inventory management
          Puavo::Inventory::device_modified(logger, Puavo::CONFIG['inventory_management'], @device, current_organisation.organisation_key)
        end
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
    unless is_owner? || current_user.has_admin_permission?(:delete_devices)
      flash[:alert] = t('flash.you_must_be_an_owner')
      redirect_to devices_url
      return
    end

    @device = get_device(params[:id])
    return if @device.nil?

    # FIXME, revoke certificate only if device's include certificate
    @device.revoke_certificate(current_organisation.organisation_key, @authentication.dn, @authentication.password)
    @device.destroy

    if Puavo::CONFIG['inventory_management']
      # Notify the external inventory management
      Puavo::Inventory::device_deleted(logger, Puavo::CONFIG['inventory_management'], params[:id].to_i)
    end

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

  def clear_reset_mode
    unless is_owner? || current_user.has_admin_permission?(:reset_devices)
      flash[:alert] = t('flash.you_must_be_an_owner')
      redirect_to devices_url
      return
    end

    @device = get_device(params[:id])
    return if @device.nil?

    @device.puavoDeviceReset = nil
    @device.save!

    respond_to do |format|
      format.html { redirect_to(device_path(@school, @device), :notice => t('flash.clear_reset_mode')) }
    end
  end

  def set_reset_mode
    unless is_owner? || current_user.has_admin_permission?(:reset_devices)
      flash[:alert] = t('flash.you_must_be_an_owner')
      redirect_to devices_url
      return
    end

    @device = get_device(params[:id])
    return if @device.nil?

    @device.set_reset_mode(current_user)
    @device.save!

    respond_to do |format|
      format.html { redirect_to(device_path(@school, @device)) }
    end
  end

  # GET /:school_id/devices/:id/select_school
  def select_school
    @device = Device.find(params[:id])
    @schools = School.all.select{ |s| s.id != @school.id }

    unless is_owner?
      # School admins can only transfer devices between the schools they're admins in
      schools = Set.new(Array(current_user.puavoAdminOfSchool || []).map { |dn| dn.to_s })
      @schools.delete_if { |s| !schools.include?(s.dn.to_s) }
    end

    # The current school is not shown on the list, so it can be empty.
    if @schools.count < 1
      flash[:notice] = t('flash.devices.no_other_schools')
      redirect_to device_path(@school, @device)
    end

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

    if Puavo::CONFIG['inventory_management']
      # Notify the external inventory management
      Puavo::Inventory::device_modified(logger, Puavo::CONFIG['inventory_management'], @device, current_organisation.organisation_key)
    end

    respond_to do |format|
      format.html{ redirect_to(device_path(@school, @device), :notice => t('flash.devices.school_changed') ) }
    end
  end

  def edit_puavomenu
    @device = Device.find(params[:id])

    unless @pme_enabled
      flash[:error] = 'Puavomenu Editor has not been enabled in this organisation'
      return redirect_to(device_path(@school, @device))
    end

    @pme_mode = :device

    @menudata = load_menudata(@device.puavoMenuData)
    @conditions = get_conditions

    respond_to do |format|
      format.html { render 'puavomenu_editor/puavomenu_editor' }
    end
  end

  def save_puavomenu
    save_menudata do |menudata, response|
      @device = Device.find(params[:id])

      @device.puavoMenuData = menudata.to_json
      @device.save!

      response[:redirect] = device_puavomenu_path(@school, @device)
    end
  end

  def clear_puavomenu
    @device = Device.find(params[:id])
    @device.puavoMenuData = nil
    @device.save!

    flash[:notice] = t('flash.puavomenu_editor.cleared')
    redirect_to(device_path(@school, @device))
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
      :puavoNotes,
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

    clean_image_name(p)

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
