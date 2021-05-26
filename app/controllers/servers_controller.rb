class ServersController < ApplicationController

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

  # New AJAX-based index for non-test environments
  def new_cool_devices_index
    @is_owner = is_owner?

    respond_to do |format|
      format.html # index.html.erb
    end
  end

  def get_servers_list
    # Which attributes to retrieve? These are the defaults, they're always
    # sent even when not requested, because basic functionality can break
    # without them.
    requested = Set.new(['id', 'hn', 'type'])

    # Extra attributes (columns)
    if params.include?(:fields)
      requested += Set.new(params[:fields].split(','))
    end

    # Do the query
    attributes = DevicesHelper.convert_requested_device_column_names(requested, is_server=true)

    # Don't get hardware info if nothing from it was requested
    hw_attributes = Set.new
    want_hw_info = false

    if (requested & DevicesHelper::HWINFO_ATTRS).any?
      attributes << 'puavoDeviceHWInfo'
      hw_attributes = DevicesHelper.convert_requested_hwinfo_column_names(requested)
      want_hw_info = true
    end

    raw = Server.search_as_utf8(:attributes => attributes)

    releases = get_releases()

    school_cache = {}

    # Convert the raw data into something we can easily parse in JavaScript
    servers = []

    raw.each do |dn, srv|
      data = {}

      # Mandatory
      data[:id] = srv['puavoId'][0].to_i
      data[:hn] = srv['puavoHostname'][0]
      data[:type] = srv['puavoDeviceType'][0]
      data[:link] = server_path(srv['puavoId'][0])
      data[:school_id] = -1
      data[:schools] = []
      data[:available_images] = []

      # Optional, common parts
      data.merge!(DevicesHelper.build_common_device_properties(srv, requested))

      # Hardware info
      if want_hw_info && srv['puavoDeviceHWInfo']
        data.merge!(DevicesHelper.extract_hardware_info(srv['puavoDeviceHWInfo'], hw_attributes))
      end

      if requested.include?('available_images') && srv.include?('puavoDeviceAvailableImage')
        srv['puavoDeviceAvailableImage'].each do |image|
          data[:available_images] << {
            file: image,
            release: releases.fetch(image, nil),
          }
        end
      end

      if requested.include?('schools') && srv.include?('puavoSchool')
        srv['puavoSchool'].each do |dn|
          # Database lookups are slow, so cache the schools
          unless school_cache.include?(dn)
            begin
              s = School.find(dn)

              school_cache[dn] = {
                valid: true,
                link: school_path(s),
                title: s.displayName,
              }
            rescue
              # Not found
              school_cache[dn] = {
                valid: false,
                dn: dn,
              }
            end
          end

          data[:schools] << school_cache[dn]
        end
      end

      # Purge empty fields to minimize the amount of transferred data
      data.delete_if{ |k, v| v.nil? }

      servers << data
    end

    render :json => servers
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

    respond_to do |format|
      format.html # show.html.erb
      format.xml  { render :xml => @server }
    end
  end

  # GET /servers/1/image
  def image
    # NEEDS TO BE EXPLICITLY TESTED
    #return 403 unless current_user && LdapOrganisation.current.owner.include?(current_user.dn)

    @server = Server.find(params[:id])

    send_data @server.jpegPhoto, :disposition => 'inline', :type => "image/jpeg"
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
    #return 403 unless current_user && LdapOrganisation.current.owner.include?(current_user.dn)

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

      strip_img(server)

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
