require 'set'
require 'groups_helper'     # For listing user groups in user tables

class OrganisationsController < ApplicationController
  include Puavo::Integrations
  include Puavo::PuavomenuEditor

  # GET /organisation
  def show
    # Argh, some LDAP tests need to use this :-(
    if request.format == 'text/html'
      return if redirected_nonowner_user?
    end

    @organisation = LdapOrganisation.current

    # Retrieve the organisation-level LDAP operational timestamps
    timestamps = LdapBase.search_as_utf8(
      filter: "(&(objectClass=puavoEduOrg)(cn=#{@organisation.cn}))",
      attributes: ['createTimestamp', 'modifyTimestamp']
    )[0][1]

    @created = Puavo::Helpers.ldap_time_string_to_utc_time(timestamps['createTimestamp'])
    @modified = Puavo::Helpers.ldap_time_string_to_utc_time(timestamps['modifyTimestamp'])

    # If the organisation has an image set, we need to display its release name
    if @organisation.puavoDeviceImage
      @release = get_releases().fetch(@organisation.puavoDeviceImage, nil)
    else
      @release = nil
    end

    # Puavomenu editor data preview
    make_puavomenu_preview(@organisation.puavoMenuData)
    @full_puavoconf = list_all_puavoconf_values(LdapOrganisation.current.puavoConf, nil, nil)

    respond_to do |format|
      format.html # show.html.erb
      format.json do
        json = JSON.parse @organisation.to_json

        json[:ldap_host] = current_organisation.value_by_key('ldap_host') || LdapBase.ensure_configuration['host']
        json[:kerberos_realm] = @organisation.puavoKerberosRealm
        json[:puavo_domain] = @organisation.puavoDomain
        json[:base] = @organisation.base.to_s
        json[:kerberos_host] = current_organisation.value_by_key('kerberos_host') || LdapBase.ensure_configuration['host']

        render json: json
      end
    end
  end

  # GET /organisation/edit
  def edit
    return if redirected_nonowner_user?

    @organisation = LdapOrganisation.current

    # Release names and the known releases selector
    @releases = get_releases
    @image_filenames_by_release = DevicesHelper.group_image_filenames_by_release(@releases)

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
        format.html { redirect_to(organisation_path) }
      else
        format.html { render action: 'edit' }
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
        format.html { redirect_to(wlan_organisation_path) }
      else
        flash[:alert] = t('flash.wlan_save_failed', error: @organisation.errors['puavoWlanSSID'].first )
        format.html { render action: 'wlan' }
      end
    end
  end

  # GET /users/owners
  def owners
    return if redirected_nonowner_user?

    # Make a list of admins who are currently organisation owners
    @current_owners = []

    owners_set().each do |dn|
      begin
        u = User.find(dn)
       rescue StandardError => e
        # Probably a removed user. LDAP isn't a relational database, so dangling references are possible.
        next
      end

      user = User.find(dn)

      @current_owners << {
        user: user,
        sort_name: "#{user['givenName']} #{user['sn']}".downcase
      }
    end

    current_owners_dn = @current_owners.collect { |o| o[:user].dn.to_s }.to_set.freeze

    # Then make a list of admin users who are not organisation owners
    @available_owners = User.find(:all, attribute: 'puavoEduPersonAffiliation', value: 'admin')
      .reject { |u| current_owners_dn.include?(u.dn.to_s) }
      .collect do |user|
      {
        user: user,
        sort_name: "#{user['givenName']} #{user['sn']}".downcase,
      }
    end

    # Sort both lists alphabetically by name
    @current_owners.sort! { |a, b| a[:sort_name] <=> b[:sort_name] }
    @available_owners.sort! { |a, b| a[:sort_name] <=> b[:sort_name] }

    # We won't display the "remove" button for the currently logged-in user
    @logged_in_user = current_user.dn.to_s
  end

  # PUT /users/add_owner/1
  def add_owner
    return if redirected_nonowner_user?

    @user = User.find(params[:user_id])

    respond_to do |format|
      if not Array(@user.puavoEduPersonAffiliation).include?('admin')
        flash[:alert] = t('flash.organisation.wrong_user_type')
      elsif LdapOrganisation.current.add_owner(@user)
        flash[:notice] = t('flash.organisation.owner_added', user: @user.displayName )
      end

      format.html { redirect_to(owners_organisation_path) }
    end
  end

  # PUT /users/remove_owner/1
  def remove_owner
    return if redirected_nonowner_user?

    @user = User.find(params[:user_id])

    # An owner cannot remove themselves from the owners (someone else has to do it). The buttons aren't shown,
    # but the URL can still be manipulated.
    if @user.dn.to_s == current_user.dn.to_s
      flash[:alert] = t('flash.organisation.cant_remove_self')
      return redirect_to(owners_organisation_path)
    end

    respond_to do |format|
      if LdapOrganisation.current.remove_owner(@user)
        flash[:notice] = t('flash.organisation.owner_removed', user: @user.displayName)
      end

      format.html { redirect_to(owners_organisation_path) }
    end
  end

  # GET /users/admins
  def all_admins
    return if redirected_nonowner_user?

    owners = owners_set()

    # Cached list of schools. Cached, because School.find() is excruciatingly slow
    @schools = {}

    def cache_school(dn)
      id = dn.rdns[0]['puavoId'].to_i

      unless @schools.include?(id)
        begin
          s = School.find(id)

          @schools[id] = {
            id: s.cn,
            name: s.displayName
          }
        rescue ActiveLdap::EntryNotFound => e
          @schools[id] = {
            id: nil,
            name: dn.to_s
          }
        end
      end

      id
    end

    # Make a list of admins
    @admins = User.find(:all, attribute: 'puavoEduPersonAffiliation', value: 'admin').collect do |admin|
      primary_school = cache_school(admin.primary_school.dn)

      {
        # These two fields are needed by the SuperTable code
        _puavo_id: admin.id.to_i,
        _school_id: admin.primary_school.id.to_i,

        id: admin.id.to_i,
        school_id: primary_school,
        name: "#{admin.givenName} #{admin.sn}",
        username: admin.uid,
        owner: owners.include?(admin.dn.to_s),
        primary_school: nil,          # placeholder for synthetic data
        other_schools: Array(admin.puavoSchool || []).map(&method(:cache_school)) - [primary_school],
        admin_in: Array(admin.puavoAdminOfSchool || []).map(&method(:cache_school)),
        permissions: Array(admin.puavoAdminPermissions || []),
      }
    end

    respond_to do |format|
      format.html   # all_admins.html.erb
    end
  end

  # GET /all_users
  def all_users
    return if redirected_nonowner_user?

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

    # You can't get here unless you're an owner
    @is_owner = true
    @permit_user_deletion = true
    @permit_mass_user_deletion = true
    @permit_user_mass_edit_expiration_times = true

    respond_to do |format|
      format.html   # all_users.html.erb
    end
  end

  # AJAX call
  def get_all_users
    schools_by_dn = raw_schools_by_dn()
    groups, group_members = GroupsHelper.load_group_member_lists(schools_by_dn, Set.new)
    krb_auth_times_by_uid = Kerberos.all_auth_times_by_uid

    # Make a list of all devices with the primary user set
    puavoid_extractor = /puavoId=([^, ]+)/.freeze
    user_devices = {}

    Device.search_as_utf8(
      filter: "(puavoDevicePrimaryUser=*)",
      scope: :one,
      attributes: ['puavoDevicePrimaryUser', 'puavoHostname', 'puavoSchool', 'puavoId']
    ).each do |dn, device|
      user_dn = device['puavoDevicePrimaryUser'][0]
      user_devices[user_dn] ||= []

      user_devices[user_dn] << {
        'id' => device['puavoId'][0].to_i,
        'school_id' => device['puavoSchool'][0].match(puavoid_extractor)[1].to_i,
        'school_dn' => device['puavoSchool'][0],
        'hostname' => device['puavoHostname'][0],
      }
    end

    render json: {
      users: User.search_as_utf8(filter: '(puavoSchool=*)', scope: :one, attributes: UsersHelper.users_raw_query_attributes),
      schools: schools_by_dn,
      school_admins: list_school_admins(),
      owners: owners_set(),
      groups: groups,
      group_members: group_members,
      devices: user_devices,
      krb_auth_times: krb_auth_times_by_uid,
    }
  end

  def all_groups
    return if redirected_nonowner_user?

    # You can't get here unless you're an owner
    @is_owner = true
    @permit_group_deletion = true
    @permit_mass_group_deletion = true

    respond_to do |format|
      format.html   # all_groups.html.erb
    end
  end

  # AJAX call
  def get_all_groups
    groups = Group.search_as_utf8(filter: '(puavoSchool=*)', scope: :one, attributes: GroupsHelper.groups_raw_query_attributes)

    # Change the members list into a members count
    groups.each do |_, g|
      g['members_count'] = [g.fetch('memberUid', []).count]
      g.delete('memberUid')
    end

    render json: {
      groups: groups,
      schools: raw_schools_by_dn()
    }
  end

  def all_devices
    return if redirected_nonowner_user?

    # List ALL schools, hide nothing
    @school_list = DevicesHelper.device_school_change_list(true, nil, nil)

    # You can't get here unless you're an owner
    @is_owner = true
    @permit_device_deletion = true
    @permit_device_mass_deletion = true
    @permit_device_reset = true
    @permit_device_mass_reset = true
    @permit_device_mass_edit_purchase_info = true
    @permit_device_mass_tag_editor = true
    @permit_device_mass_edit_expiration_times = true
    @permit_device_mass_set_db_fields = true
    @permit_device_mass_edit_puavoconf = true

    respond_to do |format|
      format.html   # all_devices.html.erb
    end
  end

  # AJAX call
  def get_all_devices
    devices = Device.search_as_utf8(filter: '(puavoSchool=*)', scope: :one,
                                    attributes: DevicesHelper.get_device_attributes)

    DevicesHelper.fill_in_device_primary_users(devices)

    render json: {
      devices: devices,
      schools: raw_schools_by_dn(),
      releases: get_releases(),
    }
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
      if !current_user || owners_set().include?(current_user.dn)
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

  def organisation_params
    o = params.require(:ldap_organisation).permit(
      :o,
      :puavoEduOrgAbbreviation,
      :description,
      :puavoOrganisationOID,
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
    o
  end

  # In some organisations, "Schools.all" can be *very* slow (I've seen 4-5 seconds per call) and we don't
  # even need 99% of the data it returns. But this raw search is nearly instantaneous. We'll lose user_path()
  # because we don't have School objects anymore, but it's no big deal, we can format URLs by hand. The
  # same pattern repeats in all of these AJAX endpoints in this controller.
  def raw_schools_by_dn
    School.search_as_utf8(attributes: %w[cn displayName puavoId]).to_h do |dn, school|
      [dn,
      {
        id: school['puavoId'][0].to_i,
        cn: school['cn'][0],
        name: school['displayName'][0]
      }]
    end
  end
end
