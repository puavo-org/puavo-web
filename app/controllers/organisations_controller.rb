require 'set'

class OrganisationsController < ApplicationController
  include Puavo::Integrations
  include Puavo::PuavomenuEditor

  # GET /organisation
  def show
    # argh, some LDAP tests need to use this :-(
    if request.format == 'text/html'
      return if redirected_nonowner_user?
    end

    @organisation = LdapOrganisation.current
    @release = nil

    if @organisation.puavoDeviceImage
      @release = get_releases().fetch(@organisation.puavoDeviceImage, nil)
    end

    make_puavomenu_preview(@organisation.puavoMenuData)

    @full_puavoconf = list_all_puavoconf_values(LdapOrganisation.current.puavoConf, nil, nil)

    # Dig up the organisation-level timestamps
    timestamps = LdapBase.search_as_utf8(:filter => "(&(objectClass=puavoEduOrg)(cn=#{@organisation.cn}))",
                                         :attributes => ["createTimestamp", "modifyTimestamp"])

    @created = convert_timestamp(Time.at(Puavo::Helpers::convert_ldap_time(timestamps[0][1]['createTimestamp'])))
    @modified = convert_timestamp(Time.at(Puavo::Helpers::convert_ldap_time(timestamps[0][1]['modifyTimestamp'])))

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

    Array(LdapOrganisation.current.owner).each.select do |dn|
      dn != "uid=admin,o=puavo"
    end.each do |dn|
      begin
        @current_owners << {
          user: User.find(dn),
          schools: [],
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

  # GET /users/admins
  def all_admins
    return if redirected_nonowner_user?

    # Current organisation owners
    owners = Array(LdapOrganisation.current.owner)
      .select { |dn| dn != 'uid=admin,o=puavo' }
      .collect { |dn| dn.to_s }
      .to_set.freeze

    # Cached list of schools. Cached, because School.find() is excruciatingly slow
    @schools = {}

    def cache_school(dn)
      id = dn.rdns[0]['puavoId'].to_i

      unless @schools.include?(id)
        s = School.find(id)

        @schools[id] = {
          id: s.cn,
          name: s.displayName
        }
      end

      id
    end

    # Make a list of admins
    @admins = User.find(:all, attribute: 'puavoEduPersonAffiliation', value: 'admin').collect do |admin|
      primary_school = cache_school(admin.primary_school.dn)

      {
        id: admin.id.to_i,            # the supertable code needs this
        school_id: primary_school,    # this too (we need a separate member for the primary school)
        name: "#{admin.givenName} #{admin.sn}",
        username: admin.uid,
        owner: owners.include?(admin.dn.to_s),
        primary_school: admin.primary_school.to_s,
        other_schools: Array(admin.puavoSchool || []).map(&method(:cache_school)) - [primary_school],
        admin_in: Array(admin.puavoAdminOfSchool || []).map(&method(:cache_school)),
        permissions: Array(admin.puavoAdminPermissions || []),
      }
    end

    respond_to do |format|
      format.html   # all_admins.html.erb
    end
  end

  def all_users
    return if redirected_nonowner_user?

    # You can't get here unless you're an owner
    @is_owner = true

    # Yes, you can
    @permit_user_deletion = true
    @permit_mass_user_deletion = true

    @automatic_email_addresses, _ = get_automatic_email_addresses

    # Make a list of synchronised deletions in ALL schools. Because every user has
    # a school ID in their row data, we can display precise warning messages about
    # each and every operation, but only if we know about per-school deletions.
    @synchronised_deletions = {}
    @synchronised_deletions_by_school = {}

    @schools_list = []

    School.all.each do |s|
      @schools_list << {
        id: s.id.to_i,
        dn: s.dn.to_s,
        name: s.displayName,
      }

      deletions = list_school_synchronised_deletion_systems(@organisation_name, s.id.to_i)
      next if deletions.empty?

      @synchronised_deletions[s.id.to_i] = deletions.to_a.sort
      @synchronised_deletions_by_school[s.displayName] = deletions.to_a.sort
    end

    # Allow moving users to any school
    @allowed_destination_schools = @schools_list

    @current_user_id = current_user.id

    respond_to do |format|
      format.html   # all_users.html.erb
    end
  end

  # AJAX call
  def get_all_users
    # Get a list of organisation owners and school admins
    organisation_owners = Array(LdapOrganisation.current.owner)
                          .reject { |dn| dn == 'uid=admin,o=puavo' }
                          .collect { |o| o.to_s }

    organisation_owners = Array(organisation_owners || []).to_set

    # Perform the admin search as a raw query. In some organisations, "Schools.all"
    # can be *very* slow (I've seen 4-5 seconds per call) and we don't even need
    # 99% of the data it returns. But this raw search is nearly instantaneous. We'll
    # lose user_path() because we don't have School objects anymore, but it's no big
    # deal, we can format URLs by hand. The same pattern repeats in all of these
    # AJAX endpoints in this controller.
    schools_by_dn = {}
    school_admins = Set.new

    School.search_as_utf8(:filter => '',
                          :attributes => ['cn', 'displayName', 'puavoId', 'puavoSchoolAdmin']).each do |dn, school|
      schools_by_dn[dn] = {
        id: school['puavoId'][0].to_i,
        cn: school['cn'][0],
        name: school['displayName'][0].force_encoding('utf-8'),
      }

      Array(school['puavoSchoolAdmin'] || []).each{ |dn| school_admins << dn }
    end

    # Get a raw list of all users in all schools
    raw = User.search_as_utf8(:filter => '(puavoSchool=*)',
                              :scope => :one,
                              :attributes => UsersHelper.get_user_attributes())

    # Convert the raw data into something we can easily parse in JavaScript
    users = []

    raw.each do |dn, usr|
      school = schools_by_dn[usr['puavoEduPersonPrimarySchool'][0]]

      # Common attributes
      user = UsersHelper.convert_raw_user(dn, usr, organisation_owners, school_admins)

      # Special attributes
      user[:link] = "/users/#{school[:id]}/users/#{user[:id]}"
      user[:school] = [school[:cn], school[:name]]
      user[:school_id] = school[:id]
      user[:schools] = Array(usr['puavoSchool'].map { |dn| schools_by_dn[dn][:id] }) - [school[:id]]

      users << user
    end

    render :json => users
  end

  def all_groups
    return if redirected_nonowner_user?

    # You can't get here unless you're an owner
    @is_owner = true

    # Yes, you can
    @permit_group_deletion = true
    @permit_mass_group_deletion = true

    respond_to do |format|
      format.html   # all_groups.html.erb
    end
  end

  # AJAX call
  def get_all_groups
    # See the explanation in get_all_users() if you're wondering why we're
    # doing a raw school search instead of School.all
    schools_by_dn = {}

    School.search_as_utf8(:filter => '',
                          :attributes => ['cn', 'displayName', 'puavoId']).each do |dn, school|
      schools_by_dn[dn] = {
        id: school['puavoId'][0].to_i,
        cn: school['cn'][0],
        name: school['displayName'][0],
      }
    end

    # Get a raw list of all groups in all schools
    raw = Group.search_as_utf8(:filter => '(puavoSchool=*)',
                               :scope => :one,
                               :attributes => GroupsHelper.get_group_attributes())

    # Convert the raw data into something we can easily parse in JavaScript
    groups = []

    raw.each do |dn, grp|
      school = schools_by_dn[grp['puavoSchool'][0]]

      # Common attributes
      group = GroupsHelper.convert_raw_group(dn, grp)

      # Special attributes
      group[:link] = "/users/#{school[:id]}/groups/#{group[:id]}"
      group[:school] = [school[:cn], school[:name]]
      group[:school_id] = school[:id]

      groups << group
    end

    render :json => groups
  end

  def all_devices
    return if redirected_nonowner_user?

    # You can't get here unless you're an owner
    @is_owner = true

    # Yes, you can
    @permit_device_deletion = true
    @permit_device_mass_deletion = true
    @permit_device_reset = true
    @permit_device_mass_reset = true

    # List ALL schools, hide nothing
    @school_list = DevicesHelper.device_school_change_list(true, nil, nil)

    respond_to do |format|
      format.html   # all_devices.html.erb
    end
  end

  # AJAX call
  def get_all_devices
    # See the explanation in get_all_users() if you're wondering why we're
    # doing a raw school search instead of School.all
    schools_by_dn = {}

    School.search_as_utf8(:filter => '',
                          :attributes => ['cn', 'displayName', 'puavoId']).each do |dn, school|
      schools_by_dn[dn] = {
        id: school['puavoId'][0].to_i,
        cn: school['cn'][0],
        name: school['displayName'][0],
      }
    end

    # Get a raw list of all devices in all schools
    raw = Device.search_as_utf8(:filter => "(puavoSchool=*)",
                                :scope => :one,
                                :attributes => DevicesHelper.get_device_attributes())

    # Known image release names
    releases = get_releases()

    # Convert the raw data into something we can easily parse in JavaScript
    devices = []

    raw.each do |dn, dev|
      school = schools_by_dn[dev['puavoSchool'][0]]

      # Common attributes
      device = DevicesHelper.convert_raw_device(dev, releases)

      # Special attributes
      device[:link] = "/devices/#{school[:id]}/devices/#{device[:id]}"
      device[:school] = [school[:cn], school[:name]]
      device[:school_id] = school[:id]

      # Figure out the primary user
      if device[:user]
        device[:user] = DevicesHelper.format_device_primary_user(device[:user], school[:id])
      end

      devices << device
    end

    render :json => devices
  end

  def edit_puavomenu
    return if redirected_nonowner_user?

    unless @pme_enabled
      flash[:error] = 'Puavomenu Editor has not been enabled in this organisation'
      return redirect_to(schools_path)
    end

    @pme_mode = :organisation

    @menudata = load_menudata(LdapOrganisation.current.puavoMenuData)
    @conditions = get_conditions

    respond_to do |format|
      format.html { render 'puavomenu_editor/puavomenu_editor' }
    end
  end

  def save_puavomenu
    save_menudata do |menudata, response|
      if !current_user || !Array(LdapOrganisation.current.owner).include?(current_user.dn)
        # Only organisation owners can edit this data
        logger.error("save_organisation: user #{current_user ? current_user.dn.to_s : '?' } is not an organisation owner")

        response[:success] = false
        response[:message] = 'Permission denied. You are not an owner.'
        false
      else
        o = LdapOrganisation.current
        o.puavoMenuData = menudata.to_json
        o.save!

        response[:redirect] = organisation_puavomenu_path
        true
      end
    end
  end

  def clear_puavomenu
    o = LdapOrganisation.current
    o.puavoMenuData = nil
    o.save!

    flash[:notice] = t('flash.puavomenu_editor.cleared')
    redirect_to(organisation_puavomenu_path)
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
        end

        # sort the schools alphabetically
        o[:schools].sort!{ |a, b| a.displayName.downcase <=> b.displayName.downcase }
      end
    end

    def organisation_params
      o = params.require(:ldap_organisation).permit(
        :o,
        :puavoEduOrgAbbreviation,
        :description,
        :puavoNotes,
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

      clean_image_name(o)

      clear_puavoconf(o)

      return o
    end

end
