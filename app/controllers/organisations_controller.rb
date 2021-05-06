class OrganisationsController < ApplicationController

  # GET /organisation
  def show
    # argh, some LDAP tests need to use this :-(
    if request.format == 'text/html'
      return if redirected_nonowner_user?
    end

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
    return if redirected_nonowner_user?

    @organisation = LdapOrganisation.current

    respond_to do |format|
      format.html
    end
  end

  # PUT /organisation
  def update
    return if redirected_nonowner_user?

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

  # GET /organisation/wlan
  def wlan
    return if redirected_nonowner_user?

    @organisation = LdapOrganisation.current

    respond_to do |format|
      format.html
    end
  end

  # PUT /organisation/wlan/update
  def wlan_update
    return if redirected_nonowner_user?

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
    return if redirected_nonowner_user?

    # List of (admin) users who currently ARE the owners of this organisation
    @current_owners = []
    current_dn = Set.new

    LdapOrganisation.current.owner.each.select do |dn|
      dn != "uid=admin,o=puavo"
    end.each do |dn|
      begin
        @current_owners << {
          user: User.find(dn),
          schools: [],
          primary: nil,
        }

        current_dn << dn
      rescue
      end
    end

    # List of admin users who currently are NOT the owners of this organisation
    @available_owners = User.find(:all,
                                  :attribute => 'puavoEduPersonAffiliation',
                                  :value => 'admin')
    .delete_if do |u|
      current_dn.include?(u.dn)
    end.collect do |u|
      {
        user: u,
        schools: [],
        primary: nil,
      }
    end

    schools = {}

    @current_owners = sort_users(find_user_schools(@current_owners, schools))
    @available_owners = sort_users(find_user_schools(@available_owners, schools))

    @logged_in_user = current_user.dn.to_s
  end

  # PUT /users/add_owner/1
  def add_owner
    return if redirected_nonowner_user?

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
    return if redirected_nonowner_user?

    @user = User.find(params[:user_id])

    # Users cannot remove themselves from owners. The buttons aren't shown,
    # but the URL can still be manipulated.
    if @user.dn.to_s == current_user.dn.to_s
      flash[:alert] = t('flash.organisation.cant_remove_self')
      redirect_to(owners_organisation_path)
      return
    end

    respond_to do |format|
      if LdapOrganisation.current.remove_owner(@user)
        flash[:notice] = t('flash.organisation.owner_removed',
                           :user => @user.displayName )
      end
      format.html { redirect_to(owners_organisation_path) }
    end
  end

  def all_devices
    return if redirected_nonowner_user?

    @school_list = DevicesHelper.device_school_change_list()

    respond_to do |format|
      format.html   # all_devices.html.erb
    end
  end

  def get_all_devices
    # Se devices_controller.rb method get_school_devices_list() for details
    requested = Set.new(['school', 'id', 'hn', 'type', 'link'])

    if params.include?(:fields)
      requested += Set.new(params[:fields].split(','))
    end

    attributes = DevicesHelper.convert_requested_device_column_names(requested)

    # Don't get hardware info if nothing from it was requested
    hw_attributes = Set.new
    want_hw_info = false

    if (requested & DevicesHelper::HWINFO_ATTRS).any?
      attributes << 'puavoDeviceHWInfo'
      hw_attributes = DevicesHelper.convert_requested_hwinfo_column_names(requested)
      want_hw_info = true
    end

    # Get the devices from every school in this organisation
    raw = []

    School.all.each do |school|
      school_raw = DevicesHelper.get_devices_in_school(school.dn, attributes)

      school_raw.each do |sd|
        # include the school in the array, we'll need it for generating links and other things
        raw << [sd, school]
      end
    end

    # Convert the raw data into something we can easily parse in JavaScript
    devices = []

    raw.each do |dev_temp, school|
      dev = dev_temp[1]   # dev_temp[0] is the device's DN

      data = {}

      # Mandatory
      data[:school] = [school.cn, school.displayName]
      data[:school_id] = school.id.to_i
      data[:id] = dev['puavoId'][0].to_i
      data[:hn] = dev['puavoHostname'][0]
      data[:type] = dev['puavoDeviceType'][0]
      data[:link] = device_path(school, dev['puavoId'][0])

      # Optional, common parts
      data.merge!(DevicesHelper.build_common_device_properties(dev, requested))

      # Hardware info
      if want_hw_info && dev['puavoDeviceHWInfo']
        data.merge!(DevicesHelper.extract_hardware_info(dev['puavoDeviceHWInfo'], hw_attributes))
      end

      # Device primary user
      if requested.include?('user') && data[:user]
        dn = data[:user]

        begin
          u = User.find(dn)

          data[:user] = {
            valid: true,
            link: user_path(school, u),
            title: "#{u.uid} (#{u.givenName} #{u.sn})"
          }
        rescue
          # Not found
          data[:user] = {
            valid: false,
            dn: dn,
          }
        end
      end

      # Purge empty fields to minimize the amount of transferred data
      data.delete_if{ |k, v| v.nil? }

      devices << data
    end

    render :json => devices
  end

  def all_users
    return if redirected_nonowner_user?

    # You can't get here unless you're an owner
    @is_owner = true

    # Yes, you can
    @permit_single_user_deletion = true

    # TODO: Is there a way to do synchronised deletions here?
    @synchronised_deletions = []

    respond_to do |format|
      format.html   # all_users.html.erb
    end
  end

  def get_all_users
    # Which attributes to retrieve? These are the defaults, they're always
    # sent even when not requested, because basic functionality can break
    # without them.
    requested = Set.new(['id', 'name', 'role', 'uid', 'dnd', 'locked', 'rrt', 'school'])

    # Extra attributes (columns)
    if params.include?(:fields)
      requested += Set.new(params[:fields].split(','))
    end

    want_id = requested.include?('id')
    want_last = requested.include?('last')
    want_first = requested.include?('first')
    want_uid = requested.include?('uid')
    want_role = requested.include?('role')
    want_eid = requested.include?('eid')
    want_learner_id = requested.include?('learner_id')
    want_phone = requested.include?('phone')
    want_name = requested.include?('name')
    want_home = requested.include?('home')
    want_email = requested.include?('email')
    want_pnumber = requested.include?('pnumber')
    want_rrt = requested.include?('rrt')
    want_dnd = requested.include?('dnd')
    want_locked = requested.include?('locked')
    want_created = requested.include?('created')
    want_modified = requested.include?('modified')
    want_school = requested.include?('school')

    # Do the query
    attributes = []
    attributes << 'puavoId' if want_id
    attributes << 'sn' if want_last
    attributes << 'givenName' if want_first
    attributes << 'uid' if want_uid
    attributes << 'puavoEduPersonAffiliation' if want_role
    attributes << 'puavoExternalId' if want_eid
    attributes << 'puavoExternalData' if want_learner_id
    attributes << 'telephoneNumber' if want_phone
    attributes << 'displayName' if want_name
    attributes << 'homeDirectory' if want_home
    attributes << 'mail' if want_email
    attributes << 'puavoEduPersonPersonnelNumber' if want_pnumber
    attributes << 'puavoRemovalRequestTime' if want_rrt
    attributes << 'puavoDoNotDelete' if want_dnd
    attributes << 'puavoLocked' if want_locked
    attributes << 'createTimestamp' if want_created
    attributes << 'modifyTimestamp' if want_modified
    attributes << 'puavoSchool' if want_school

    raw = []

    # Get a list of organisation owners and school admins
    organisation_owners = LdapOrganisation.current.owner.each
      .select { |dn| dn != "uid=admin,o=puavo" }
      .map{ |o| o.to_s }

    if organisation_owners.nil?
      organisation_owners = []
    end

    organisation_owners = Set.new(organisation_owners)

    school_admins = []

    all_schools = School.all

    schools_by_dn = {}

    all_schools.each do |school|
      school_admins += school.user_school_admins.each.map{ |a| a.dn.to_s }
      schools_by_dn[school.dn.to_s] = school
    end

    school_admins = Set.new(school_admins)

    # Get a list of all users in all schools
    users = []

    raw = User.search_as_utf8(:filter => "(puavoSchool=*)",
                              :scope => :one,
                              :attributes => attributes)

    raw.each do |dn, usr|
      school = schools_by_dn[usr['puavoSchool'][0]]

      u = {}

      # Mandatory
      u[:id] = usr['puavoId'][0].to_i
      u[:uid] = usr['uid'][0]
      u[:name] = usr['displayName'] ? usr['displayName'][0] : nil
      u[:role] = Array(usr['puavoEduPersonAffiliation'])
      u[:rrt] = convert_ldap_time(usr['puavoRemovalRequestTime'])
      u[:dnd] = usr['puavoDoNotDelete'] ? true : false
      u[:locked] = usr['puavoLocked'] ? (usr['puavoLocked'][0] == 'TRUE' ? true : false) : false
      u[:link] = user_path(school, usr['puavoId'][0])
      u[:school] = [school.cn, school.displayName]
      u[:school_id] = school.id.to_i

      # Optional
      if want_first
        u[:first] = usr['givenName'] ? usr['givenName'][0] : nil
      end

      if want_last
        u[:last] = usr['sn'] ? usr['sn'][0] : nil
      end

      if want_eid
        u[:eid] = usr['puavoExternalId'] ? usr['puavoExternalId'][0] : nil
      end

      if want_phone
        u[:phone] = usr['telephoneNumber'] ? Array(usr['telephoneNumber']) : nil
      end

      if want_home
        u[:home] = usr['homeDirectory'][0]
      end

      if want_email
        u[:email] = usr['mail'] ? Array(usr['mail']) : nil
      end

      if want_pnumber
        u[:pnumber] = usr['puavoEduPersonPersonnelNumber'] ? usr['puavoEduPersonPersonnelNumber'][0] : nil
      end

      if want_created
        u[:created] = convert_ldap_time(usr['createTimestamp'])
      end

      if want_modified
        u[:modified] = convert_ldap_time(usr['modifyTimestamp'])
      end

      # Highlight organisation owners (school admins have already an "admin" role set)
      u[:role] << 'owner' if organisation_owners.include?(dn)

      # Learner ID, if present. I wonder what kind of performance impact this
      # kind of repeated JSON parsing has?
      if want_learner_id && usr.include?('puavoExternalData')
        begin
          ed = JSON.parse(usr['puavoExternalData'][0])
          if ed.include?('learner_id') && ed['learner_id']
            u[:learner_id] = ed['learner_id']
          end
        rescue
        end
      end

      users << u
    end

    render :json => users
  end

  # GET /users/find_all_users_marked_for_deletion
  # (A button on the organisation info page)
  def find_all_users_marked_for_deletion
    return if redirected_nonowner_user?

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
    return if redirected_nonowner_user?

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
        ((a[:user]["givenName"] || "") + (a[:user]["sn"] || "")).downcase <=>
          ((b[:user]["givenName"] || "") + (b[:user]["sn"] || "")).downcase
      end
    end

    def find_user_schools(l, schools_cache)
      l.each do |o|
        Array(o[:user].puavoSchool).each do |dn|
          schools_cache[dn] = School.find(dn) unless schools_cache.include?(dn)
          o[:schools] << schools_cache[dn]
          o[:primary] = schools_cache[dn] unless o[:primary]
        end
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

      strip_img(o)

      clear_puavoconf(o)

      return o
    end

end
