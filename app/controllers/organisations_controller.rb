class OrganisationsController < ApplicationController
  include Puavo::Integrations

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
    requested = Set.new(['id', 'hn', 'type'])

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

    # Get the devices from every school in this organisation. Use raw queries throughout,
    # because we don't need most of the data the objects contain. Plus, object construction
    # is significantly slower and here speed >> code cleanliness or length.
    raw = []

    schools = []

    School.search_as_utf8(:filter => '',
                          :attributes=>['cn', 'displayName', 'puavoId']).each do |dn, school|
      schools << {
        dn: dn,
        id: school['puavoId'][0].to_i,
        cn: school['cn'][0],
        name: school['displayName'][0]
      }

      school_index = schools.count - 1

      DevicesHelper.get_devices_in_school(dn, attributes).each do |d|
        # the school is required when generating links and other things
        raw << [d[1], school_index]
      end
    end

    # Convert the raw data into something we can easily parse in JavaScript
    devices = []

    raw.each do |dev, school_index|
      school = schools[school_index]

      data = {}

      # Mandatory
      data[:id] = dev['puavoId'][0].to_i
      data[:hn] = dev['puavoHostname'][0]
      data[:type] = dev['puavoDeviceType'][0]
      data[:link] = "/devices/#{school[:id]}/devices/#{dev['puavoId'][0]}"
      data[:school] = [school[:cn], school[:name]]
      data[:school_id] = school[:id]

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
            link: "/users/#{school[:id]}/users/#{u.id}",
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

    @automatic_email_addresses, _ = get_automatic_email_addresses

    # Make a list of synchronised deletions in ALL schools. Because every user has
    # a school ID in their row data, we can display precise warning messages about
    # each and every operation, but only if we know about per-school deletions.
    @synchronised_deletions = {}
    @synchronised_deletions_by_school = {}

    School.all.each do |s|
      deletions = list_school_synchronised_deletion_systems(@organisation_name, s.id.to_i)
      next if deletions.empty?

      @synchronised_deletions[s.id.to_i] = deletions.to_a.sort
      @synchronised_deletions_by_school[s.displayName] = deletions.to_a.sort
    end

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

    attributes = UsersHelper.convert_requested_user_column_names(requested)

    raw = []

    # Get a list of organisation owners and school admins
    organisation_owners = LdapOrganisation.current.owner.each
      .select { |dn| dn != "uid=admin,o=puavo" }
      .map{ |o| o.to_s }

    if organisation_owners.nil?
      organisation_owners = []
    end

    organisation_owners = Set.new(organisation_owners)

    # Perform the admin search as a raw query. In some organisations, "Schools.all"
    # can be *very* slow (like 4-5 seconds per call) and we don't even need 99% of
    # the data it returns. But this raw search is nearly instantaneous. We'll lose
    # user_path() because we don't have School objects anymore, but it's no big
    # deal, we can format the URL by hand.
    schools_by_dn = {}
    school_admins = Set.new

    School.search_as_utf8(:filter => '',
                          :attributes=>['cn', 'displayName', 'puavoId', 'puavoSchoolAdmin']).each do |dn, school|
      schools_by_dn[dn] = {
        id: school['puavoId'][0].to_i,
        cn: school['cn'][0],
        name: school['displayName'][0],
      }

      Array(school['puavoSchoolAdmin'] || []).each{ |dn| school_admins << dn }
    end

    # Get a list of all users in all schools
    users = []

    raw = User.search_as_utf8(:filter => "(puavoSchool=*)",
                              :scope => :one,
                              :attributes => attributes)

    raw.each do |dn, usr|
      school = schools_by_dn[usr['puavoSchool'][0]]

      user = {}

      # Mandatory
      user[:id] = usr['puavoId'][0].to_i
      user[:uid] = usr['uid'][0]
      user[:name] = usr['displayName'] ? usr['displayName'][0] : nil
      user[:role] = Array(usr['puavoEduPersonAffiliation'])
      user[:rrt] = Puavo::Helpers::convert_ldap_time(usr['puavoRemovalRequestTime'])
      user[:dnd] = usr['puavoDoNotDelete'] ? true : false
      user[:locked] = usr['puavoLocked'] ? (usr['puavoLocked'][0] == 'TRUE' ? true : false) : false
      user[:link] = "/users/#{school[:id]}/users/#{usr['puavoId'][0]}"
      user[:school] = [school[:cn], school[:name]]
      user[:school_id] = school[:id]

      # Highlight organisation owners (school admins have already an "admin" role set)
      user[:role] << 'owner' if organisation_owners.include?(dn)

      # Optional, common parts
      user.merge!(UsersHelper.build_common_user_properties(usr, requested))

      users << user
    end

    render :json => users
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
