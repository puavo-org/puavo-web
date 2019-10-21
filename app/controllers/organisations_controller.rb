class OrganisationsController < ApplicationController

  # GET /organisation
  def show
    @organisation = LdapOrganisation.current

    respond_to do |format|
      format.html # show.html.erb
      format.json do
        json = JSON.parse @organisation.to_json

        json[:ldap_host] = current_organisation.value_by_key("ldap_host") || LdapBase.ensure_configuration["host"]
        json[:kerberos_realm] = @organisation.puavoKerberosRealm
        json[:puavo_domain] = @organisation.puavoDomain
        json[:base] = @organisation.base.to_s
        json[:kerberos_host] = current_organisation.value_by_key("kerberos_host") || LdapBase.ensure_configuration["host"]

        render :json => json
      end
    end
  end

  # GET /organisation/edit
  def edit
    @organisation = LdapOrganisation.current

    respond_to do |format|
      format.html
    end
  end

  # PUT /organisation
  def update
    @organisation = LdapOrganisation.current

    respond_to do |format|
      if @organisation.update_attributes(organisation_params)
        flash[:notice] = t('flash.organisation.updated')
        format.html { redirect_to( organisation_path ) }
      else
        format.html { render :action => "edit" }
      end
    end
  end

  def get_organisation_devices_list
    attributes = [
      'puavoId',
      'puavoHostname',
      'puavoDeviceType',
      'puavoDeviceImage',
      'puavoDeviceCurrentImage',
      'macAddress',
      'serialNumber',
      'puavoDeviceManufacturer',
      'puavoDeviceModel',
      'puavoDeviceKernelArguments',
      'puavoDeviceXrandr',
      'puavoTag',
      'puavoConf',
      'puavoDeviceHWInfo',
      'createTimestamp',    # LDAP operational attribute
      'modifyTimestamp'     # LDAP operational attribute
    ]

    # get the devices from every school in this organisation
    @raw = []

    School.all.each do |school|
      school_raw = Device.search_as_utf8(:filter => "(puavoSchool=#{school.dn})",
                                         :scope => :one,
                                         :attributes => attributes)

      school_raw.each do |sd|
        # pack the school into the array, we'll need it when generating links and other things
        @raw << [sd, school]
      end
    end

    gigabytes = 1024 * 1024 * 1024

    # Localise device type names. We can do this in the JavaScript code too, but the table
    # sorter only sees IDs, not names, so it sorts device types incorrerctly.
    device_types = Puavo::CONFIG['device_types']

    # convert the raw data into something we can easily parse in JavaScript
    @devices = []

    @raw.each do |dev_temp, school|
      dev = dev_temp[1]   # dev_temp[0] is the device's DN

      # extract hardware info
      hw_current_image = nil
      hw_time = nil
      hw_ram = nil
      hw_hd = nil
      hw_ssd = false
      hw_wlan = nil
      hw_cpu = nil
      hw_bios_vendor = nil
      hw_bios_version = nil
      hw_bios_date = nil
      hw_bat_vendor = nil
      hw_bat_serial = nil
      hw_bat_capacity = nil

      if dev.include?('puavoDeviceHWInfo')
        begin
          info = JSON.parse(dev['puavoDeviceHWInfo'][0])

          # we have puavoImage and puavoCurrentImage fields in the database, but
          # they aren't always reliable
          hw_current_image = info['this_image']

          hw_time = info['timestamp'].to_i
          hw_ram = (info['memory'] || []).sum { |slot| slot['size'].to_i }
          hw_hd = ((info['blockdevice_sda_size'] || 0).to_i / gigabytes).to_i
          hw_ssd = info['ssd'] ? (info['ssd'] == "1") : false   # why oh why did I put a string in this field and not an integer?
          hw_wifi = info['wifi']
          hw_bios_vendor = info['bios_vendor']
          hw_bios_version = info['bios_version']
          hw_bios_date = info['bios_release_date']

          if info['processor0'] && info['processorcount']
            # combine CPU count and name
            hw_cpu = "#{info['processorcount']}×#{info['processor0']}"
          end

          if info['battery']
            hw_bat_vendor = info['battery']['vendor']
            hw_bat_serial = info['battery']['serial']
            hw_bat_capacity = info['battery']['capacity']

            if hw_bat_capacity
              # Convert the battery capacity into an integer. It's a floating-point number, with
              # a locate-specific digit separator (dot, comma) and ending in a '%'. I could keep
              # it as a float, but at the moment, I can't easily add floats to the supertable
              # (actually I can, but making filters for them is painful).

              hw_bat_capacity = hw_bat_capacity.gsub(',', '.')
              hw_bat_capacity = hw_bat_capacity.gsub('%', '')
              hw_bat_capacity = hw_bat_capacity.to_i

            end
          end
        rescue
          # oh well
        end
      end

      @devices << {
        id: dev['puavoId'][0],
        hn: dev['puavoHostname'][0],
        type: dev['puavoDeviceType'] ? device_types[dev['puavoDeviceType'][0]]['label'][I18n.locale.to_s] : nil,
        image: dev['puavoDeviceImage'] ? dev['puavoDeviceImage'][0] : nil,
        current_image: hw_current_image,
        mac: dev['macAddress'] ? Array(dev['macAddress']) : nil,
        serial: dev['serialNumber'] ? dev['serialNumber'][0] : nil,
        mfer: dev['puavoDeviceManufacturer'] ? dev['puavoDeviceManufacturer'][0] : nil,
        model: dev['puavoDeviceModel'] ? dev['puavoDeviceModel'][0] : nil,
        krn_args: dev['puavoDeviceKernelArguments'] ? dev['puavoDeviceKernelArguments'][0] : nil,
        tags: dev['puavoTag'] ? dev['puavoTag'] : nil,
        created: convert_ldap_time(dev['createTimestamp']),
        modified: convert_ldap_time(dev['modifyTimestamp']),
        hw_time: hw_time,
        xrandr: dev['puavoDeviceXrandr'] ? Array(dev['puavoDeviceXrandr']) : nil,
        bios_vendor: hw_bios_vendor,
        bios_version: hw_bios_version,
        bios_date: hw_bios_date,
        cpu: hw_cpu,
        ram: hw_ram,
        hd: hw_hd,
        hd_ssd: hw_ssd,
        wifi: hw_wifi,
        bat_vendor: hw_bat_vendor,
        bat_serial: hw_bat_serial,
        bat_cap: hw_bat_capacity,
        conf: dev['puavoConf'] ? JSON.parse(dev['puavoConf'][0]).collect{|k, v| "\"#{k}\"=\"#{v}\"" } : nil,
        school: school.displayName,
        link: device_path(school, dev['puavoId'][0]),
      }
    end

    render :json => @devices
  end

  # GET /organisation/wlan
  def wlan
    @organisation = LdapOrganisation.current

    respond_to do |format|
      format.html
    end
  end

  # PUT /organisation/wlan/update
  def wlan_update
    @organisation = LdapOrganisation.current

    @organisation.update_wlan_attributes(params)
    @organisation.puavoWlanChannel = params[:ldap_organisation][:puavoWlanChannel]

    respond_to do |format|
      if @organisation.save
        flash[:notice] = t('flash.wlan_updated')
        format.html { redirect_to( wlan_organisation_path ) }
      else
        flash[:alert] = t('flash.wlan_save_failed', :error => @organisation.errors["puavoWlanSSID"].first )
        format.html { render :action => "wlan" }
      end
    end
  end

  # GET /users/owners
  def owners

    # List of (admin) users who currently ARE the owners of this organisation
    @owners = []

    # Deleted users that still hang around in the owners list
    @missing = []

    LdapOrganisation.current.owner.each.select do |dn|
      dn != "uid=admin,o=puavo"
    end.each do |dn|
      begin
        @owners << User.find(dn)
      rescue ActiveLdap::EntryNotFound
        # This user has been removed, but their DN is
        # still listed in the "owners" array...
        puts "User #{dn} no longer exists!"
        @missing << dn
      end
    end

    # List of admin users who currently are NOT the owners of this organisation
    @allowed_owners = User.find(:all,
                                :attribute => 'puavoEduPersonAffiliation',
                                :value => 'admin').delete_if do |u|
      @owners.include?(u)
    end

    @owners = sort_users(@owners)
    @allowed_owners = sort_users(@allowed_owners)

    schools = {}

    @owners.each do |o|
      dn = o.school.dn
      schools[dn] = School.find(dn) unless schools.include?(dn)
      o.school = schools[dn]
    end

    @allowed_owners.each do |o|
      dn = o.school.dn
      schools[dn] = School.find(dn) unless schools.include?(dn)
      o.school = schools[dn]
    end

  end

  # PUT /users/add_owner/1
  def add_owner
    @user = User.find(params[:user_id])

    respond_to do |format|
      if not Array(@user.puavoEduPersonAffiliation).include?('admin')
        flash[:notice] = t('flash.organisation.wrong_user_type')
      elsif LdapOrganisation.current.add_owner(@user)
        flash[:notice] = t('flash.organisation.owner_added',
                           :user => @user.displayName )

      else

      end
      format.html { redirect_to(owners_organisation_path) }
    end
  end

  # PUT /users/remove_owner/1
  def remove_owner
    @user = User.find(params[:user_id])

    respond_to do |format|
      if LdapOrganisation.current.remove_owner(@user)
        flash[:notice] = t('flash.organisation.owner_removed',
                           :user => @user.displayName )
      end
      format.html { redirect_to(owners_organisation_path) }
    end
  end

  # GET /users/find_all_users_marked_for_deletion
  # (A button on the organisation info page)
  def find_all_users_marked_for_deletion
    unless current_user.organisation_owner?
      respond_to do |format|
        format.html { redirect_to(organisation_path) }
      end

      return
    end

    now = Time.now.utc

    # Displayed in the date range selector
    @form_dates = [
      { :title => t('organisations.deleted_users.range_all'),     :before => (now + 1.day).to_i,   :index => 0 },
      { :title => t('organisations.deleted_users.range_1month'),  :before => (now - 1.month).to_i, :index => 1 },
      { :title => t('organisations.deleted_users.range_3months'), :before => (now - 3.month).to_i, :index => 2 },
      { :title => t('organisations.deleted_users.range_6months'), :before => (now - 6.month).to_i, :index => 3 }
    ]

    # Defaults
    index = 2
    before = now - 3.month

    @form_dates[index][:default] = true

    # Resubmitted page?
    if params
      if params['index'] && !params['index'].empty?
        index = params['index'].to_i
      end

      if params['before'] && !params['before'].empty?
        before = Time.at(params['before'].to_i)
      end
    end

    # Highlight the selected date range
    if index >= 0 && index < @form_dates.count
      @form_dates[index][:selected] = true
    end

    @before = before.to_i

    # Find matching users
    @all_members = []
    @fuzzy = {}
    @total = 0

    school_list.each do |school|
      members = []

      Array(school.member || []).each do |member|
        begin
          u = User.find(member)
        rescue
          # TODO: What to do here?
          next
        end

        next if u.puavoRemovalRequestTime.nil?

        # date filter
        next if u.puavoRemovalRequestTime > before

        members << u

        # Store fuzzy timestamps separately, because we cannot modify the user
        # object. In the users controller this problem does not exist because
        # the objects are just JSON dictionaries, but here we use actual user
        # objects.
        @fuzzy[u.uid] = fuzzy_time(now - u.puavoRemovalRequestTime)

        @total += 1
      end

      next if members.empty?

      # Sort by lastname+firstnames
      members.sort! do |a, b|
        (a.sn.to_s + a.givenName.to_s).downcase <=>
        (b.sn.to_s + b.givenName.to_s).downcase
      end

      @all_members << {
        school: school,
        members: members
      }
    end

    respond_to do |format|
      format.html { render :action => "marked_for_deletion" }
    end
  end

  # DELETE /users/find_all_users_marked_for_deletion
  def delete_all_users_marked_for_deletion
    if !params || !params['before'] || params['before'].empty?
      flash[:alert] = t('organisations.deleted_users.missing_date')
      redirect_to find_all_users_marked_for_deletion_path
      return
    end

    before = Time.at(params['before'].to_i)

    # Delete them
    total = 0
    errors = 0

    school_list.each do |school|
      Array(school.member || []).each do |member|
        begin
          u = User.find(member)
        rescue
          errors += 1
          next
        end

        next if u.puavoRemovalRequestTime.nil?

        # date filter
        next if u.puavoRemovalRequestTime > before

        begin
          u.destroy
          total += 1
        rescue StandardError => e
          puts e
          errors += 1
        end
      end
    end

    if errors == 0
      flash[:notice] = t('organisations.deleted_users.users_deleted_ok', :count => total)
    else
      flash[:notice] = t('organisations.deleted_users.users_deleted_fail', :count => total)
    end

    redirect_to find_all_users_marked_for_deletion_path
  end

  private
    def sort_users(l)
      l.sort! do |a, b|
        ((a["givenName"] || "") + (a["sn"] || "")).downcase <=>
          ((b["givenName"] || "") + (b["sn"] || "")).downcase
      end
    end

    def organisation_params
      o = params.require(:ldap_organisation).permit(
        :o,
        :puavoEduOrgAbbreviation,
        :description,
        :telephoneNumber,
        :facsimileTelephoneNumber,
        :l,
        :street,
        :postOfficeBox,
        :postalAddress,
        :postalCode,
        :st,
        :puavoLocale,
        :puavoTimezone,
        :puavoKeyboardLayout,
        :puavoKeyboardVariant,
        :puavoAutomaticImageUpdates,
        :eduOrgHomePageURI,
        :puavoDeviceAutoPowerOffMode,
        :puavoDeviceOnHour,
        :puavoDeviceOffHour,
        :puavoDeviceImage,
        :puavoConf,
        :puavoImageSeriesSourceURL=>[],
        :puavoBillingInfo=>[]
      ).to_hash

      return o
    end

end
