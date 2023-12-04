require_relative '../../rest/lib/inventory.rb'

class ServersController < ApplicationController
  include Puavo::Inventory

  # GET /servers
  # GET /servers.xml
  def index
    if test_environment? || ['application/json', 'application/xml'].include?(request.format)
      old_legacy_devices_index
    else
      new_cool_devices_index
    end
  end

  # Old "legacy" index used during tests
  def old_legacy_devices_index
    return if redirected_nonowner_user?

    @servers = Server.all
    @servers = @servers.sort{ |a, b| a.puavoHostname.downcase <=> b.puavoHostname.downcase }

    respond_to do |format|
      format.html # index.html.erb
      format.xml  { render :xml => @servers }
    end
  end

  # New AJAX-based index for non-test environments
  def new_cool_devices_index
    return if redirected_nonowner_user?

    @is_owner = is_owner?

    @servers = get_servers_list

    respond_to do |format|
      format.html # index.html.erb
    end
  end

  # AJAX call
  def get_servers_list
    # See the explanation in OrganisationsController::get_all_users() if you're wondering why we're
    # doing a raw school search instead of School.all
    schools_by_dn = {}

    School.search_as_utf8(:filter => '',
                          :attributes => ['cn', 'displayName', 'puavoId']).each do |dn, school|
      schools_by_dn[dn] = {
        name: school['displayName'][0],
        link: "/users/schools/#{school['puavoId'][0]}",
      }
    end

    # Get a raw list of servers in this organisation
    raw = Server.search_as_utf8(:attributes => DevicesHelper.get_server_attributes())

    # Known image release names
    releases = get_releases()

    # Convert the raw data into something we can easily parse in JavaScript
    school_cache = {}
    servers = []

    raw.each do |dn, srv|
      # Common attributes
      server = DevicesHelper.convert_raw_device(srv, releases)

      # Special attributes
      server[:link] = "/devices/servers/#{server[:id]}"
      server[:school_id] = -1   # servers are not bound to any specific school

      if srv.include?('puavoDeviceAvailableImage')
        images = []

        Array(srv['puavoDeviceAvailableImage'] || []).each do |image|
          images << {
            file: image,
            release: releases.fetch(image, nil),
          }
        end

        if images.count > 0
          server[:available_images] = images
        end
      end

      # In servers, the puavoSchool attribute lists which schools the server serves
      if srv.include?('puavoSchool')
        schools = []

        Array(srv['puavoSchool'] || []).each do |dn|
          if schools_by_dn.include?(dn)
            s = schools_by_dn[dn]

            schools << {
              valid: true,
              title: s[:name],
              link: s[:link],
            }
          else
            schools << {
              valid: false,
              dn: dn,
            }
          end
        end

        if schools.count > 0
          server[:schools] = schools
        end
      end

      servers << server
    end

    servers
  end

  # GET /servers/1
  # GET /servers/1.xml
  def show
    return if redirected_nonowner_user?

    @server = get_server(params[:id])
    return if @server.nil?

    @server = Server.find(params[:id])
    @server.get_certificate(current_organisation.organisation_key, @authentication.dn, @authentication.password)
    @server.get_ca_certificate(current_organisation.organisation_key)

    # get the creation and modification timestamps from LDAP operational attributes
    extra = Server.find(params[:id], :attributes => ['createTimestamp', 'modifyTimestamp'])
    @server['createTimestamp'] = convert_timestamp(extra['createTimestamp'])
    @server['modifyTimestamp'] = convert_timestamp(extra['modifyTimestamp'])

    @releases = get_releases

    @fqdn = "#{@server.puavoHostname}.#{LdapOrganisation.current.puavoDomain}"

    @full_puavoconf = list_all_puavoconf_values(LdapOrganisation.current.puavoConf, nil, @server.puavoConf)

    respond_to do |format|
      format.html # show.html.erb
      format.xml  { render :xml => @server }
    end
  end

  # GET /servers/1/image
  def image
    # NEEDS TO BE EXPLICITLY TESTED
    #return 403 unless current_user && Array(LdapOrganisation.current.owner).include?(current_user.dn)

    @server = Server.find(params[:id])

    send_data @server.jpegPhoto, :disposition => 'inline', :type => "image/jpeg"
  end

  # GET servers/:id/raw_hardware_info
  def raw_hardware_info
    server = Server.find(params[:id])
    data = {}

    begin
      data = JSON.parse(server.puavoDeviceHWInfo)
    rescue => e
    end

    send_data data.to_json,
              type: :json,
              disposition: "attachment",
              filename: "#{current_organisation.organisation_key}-#{server.cn}.json"
  end

  # GET /servers/new
  # GET /servers/new.xml
  def new
    return if redirected_nonowner_user?

    @server = Server.new

    respond_to do |format|
      format.html # new.html.erb
      format.xml  { render :xml => @server }
      format.json
    end
  end

  # GET /servers/1/edit
  def edit
    return if redirected_nonowner_user?

    @server = get_server(params[:id])
    return if @server.nil?

    @server = Server.find(params[:id])
    @schools = School.all
    @server.get_certificate(current_organisation.organisation_key, @authentication.dn, @authentication.password)
  end

  # POST /servers
  # POST /servers.xml
  def create
    # NEEDS TO BE EXPLICITLY TESTED
    #return 403 unless current_user && Array(LdapOrganisation.current.owner).include?(current_user.dn)

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
        if Puavo::CONFIG['inventory_management']
          # Notify the external inventory management
          Puavo::Inventory::device_created(logger, Puavo::CONFIG['inventory_management'], @server, current_organisation.organisation_key)
        end
        flash[:notice] = t('flash.server_created')
        format.html { redirect_to(server_path(@server)) }
        format.xml  { render :xml => @server, :status => :created, :location => server_path(@server) }
        format.json  { render :json => @server, :status => :created, :location => server_path(@server) }
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
    return if redirected_nonowner_user?

    @server = get_server(params[:id])
    return if @server.nil?

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
        if Puavo::CONFIG['inventory_management']
          # Notify the external inventory management
          Puavo::Inventory::device_modified(logger, Puavo::CONFIG['inventory_management'], @server, current_organisation.organisation_key)
        end
        flash[:notice] = t('flash.server_updated')
        format.html { redirect_to(server_path(@server)) }
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
    return if redirected_nonowner_user?

    @server = Server.find(params[:id])
    # FIXME, revoke certificate only if device's include certificate
    @server.revoke_certificate(current_organisation.organisation_key, @authentication.dn, @authentication.password)
    @server.destroy

    # FIXME: remove printers of this server!

    if Puavo::CONFIG['inventory_management']
      # Notify the external inventory management
      Puavo::Inventory::device_deleted(logger, Puavo::CONFIG['inventory_management'], params[:id].to_i)
    end

    respond_to do |format|
      format.html { redirect_to(servers_url) }
      format.xml  { head :ok }
    end
  end

  # DELETE /servers/1
  def revoke_certificate
    return if redirected_nonowner_user?

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
        :devicetype,                    # used when registering a boot server
        :host_certificate_request,      # used when registering a boot server
        :puavoDeviceType,               # used when registering a boot server
        :puavoAutomaticImageUpdates,    # used when registering a boot server
        :puavoPersonallyAdministered,   # used when registering a boot server
        :puavoPersonalDevice,           # used when registering a boot server
        :puavoHostname,
        :puavoTag,
        :puavoConf,
        :puavoDeviceStatus,
        :image,
        :puavoDeviceManufacturer,
        :puavoDeviceModel,
        :serialNumber,
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

      # For some reason, server parameters have been split into
      # multiple hashes and each one must be permitted separately.
      # Perhaps there is a better way to do this?
      device = {}

      if params.include?(:device)
        # boot server registration does not send :device parameters
        device = params.require(:device).permit(
          :puavoDeviceMonitorsXML=>[],
          :puavoDeviceXrandr=>[],
        ).to_hash
      end

      # deduplicate arrays, as LDAP really does not like duplicate entries...
      server["puavoTag"] = server["puavoTag"].split.uniq.join(' ') if server.key?("puavoTag")
      server["puavoExport"].uniq! if server.key?("puavoExport")
      server["macAddress"].uniq! if server.key?("macAddress")
      server["puavoImageSeriesSourceURL"].uniq! if server.key?("puavoImageSeriesSourceURL")
      device["puavoDeviceXrandr"].uniq! if device.key?("puavoDeviceXrandr")

      clear_puavoconf(server)

      clean_image_name(server)

      return server.merge(device)

    end

    def get_server(id)
      begin
        return Server.find(id)
      rescue ActiveLdap::EntryNotFound => e
        flash[:alert] = t('flash.invalid_server_id', :id => id)
        redirect_to servers_path
        return nil
      end
    end

end
