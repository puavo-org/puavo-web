require 'set'
require 'devices_helper'    # Need clear_device_primary_user

class UsersController < ApplicationController
  include Puavo::Integrations
  include Puavo::UsersShared
  include Puavo::Password

  # GET /:school_id/users
  # GET /:school_id/users.xml
  def index
    if test_environment? || ['application/json', 'application/xml'].include?(request.format)
      old_legacy_users_index
    else
      new_cool_users_index
    end
  end

  # Old "legacy" index used during tests
  def old_legacy_users_index
    if @school
      filter = "(puavoSchool=#{@school.dn})"
    end
    attributes = ['sn', 'givenName', 'uid', 'puavoEduPersonAffiliation', 'puavoId',
                  'puavoSchool',
                  'telephoneNumber',
                  'displayName',
                  'gidNumber',
                  'mail',
                  'sambaSID',
                  'uidNumber',
                  'loginShell',
                  'puavoAdminOfSchool',
                  'sambaPrimaryGroupSID',
                  'puavoRemovalRequestTime',
                  'puavoDoNotDelete',
                  'puavoLocked',
                  'puavoExternalId']

    @users = User.search_as_utf8( :filter => filter,
                          :scope => :one,
                          :attributes => attributes )

    @users = @users.map do |user|
      # ldap values are always arrays. Convert hash values from arrays by
      # grabbing the first value
      Hash[user.last.map { |k,v| [k, v.first] }]
    end.sort do |a,b|
      (a["sn"].to_s + a["givenName"].to_s).downcase <=> (b["sn"].to_s + b["givenName"].to_s).downcase
    end

    if request.format == 'application/json'
      @users = @users.map{ |u| User.build_hash_for_to_json(u) }
    else
      now = Time.now.utc

      @users.each do |u|
        next if u["puavoRemovalRequestTime"].nil?

        # The timestamp is a Net::BER::BerIdentifiedString, convert it into
        # an actual UTC timestamp
        timestamp = Time.strptime(u["puavoRemovalRequestTime"], '%Y%m%d%H%M%S%z')
        u["puavoExactRemovalTimeRaw"] = timestamp.to_i
        u["puavoExactRemovalTime"] = convert_timestamp(timestamp)
        u["puavoFuzzyRemovalTime"] = fuzzy_time(now - timestamp)
      end
    end

    # These have to be set, because there are tests for the admin rights
    # (don't bother with mass deletion, as that tool is only available
    # through JavaScript and the tests don't run JS)
    @is_owner = is_owner?
    @permit_user_creation = @is_owner || current_user.has_admin_permission?(:create_users)
    @permit_user_deletion = @is_owner || current_user.has_admin_permission?(:delete_users)

    respond_to do |format|
      format.html # index.html.erb
      format.xml  { render :xml => @users }
      format.json { render :json => @users }
    end
  end

  # New AJAX-based index for non-test environments
  def new_cool_users_index
    @is_owner = is_owner?
    @permit_user_creation = @is_owner || current_user.has_admin_permission?(:create_users)
    @permit_user_deletion = @is_owner || current_user.has_admin_permission?(:delete_users)
    @permit_mass_user_deletion = @is_owner || (@permit_user_deletion && current_user.has_admin_permission?(:mass_delete_users))

    @automatic_email_addresses, _ = get_automatic_email_addresses

    # Make a list of all schools in this organisation. Even limited users who can't access all
    # schools must still see their names, so they can be listed in "other schools" lists for
    # users.
    @schools_list = []

    School.all.each do |s|
      @schools_list << {
        id: s.id.to_i,
        dn: s.dn.to_s,
        name: s.displayName,
      }
    end

    # We'll maintain a separate list of schools this user is allowed to access. Unused for owners.
    @allowed_schools = @is_owner ? nil : Array(current_user.puavoAdminOfSchool || []).map(&:to_s).to_set

    # A list of schools where the current user (admin or owner) can move other users to. It can be empty.
    @allowed_destination_schools = []

    @schools_list.each do |s|
      next if !@allowed_schools.nil? && !@allowed_schools.include?(s[:dn])
      next if !@is_organisation && s[:dn] == @school.dn.to_s
      @allowed_destination_schools << s
    end

    # List of systems where user deletions are synchronised
    @synchronised_deletions = {}
    deletions = list_school_synchronised_deletion_systems(@organisation_name, school.id.to_i)

    @current_user_id = current_user.id

    unless deletions.empty?
      @synchronised_deletions[school.id.to_i] = deletions.to_a.sort
    end

    respond_to do |format|
      format.html # index.html.erb
    end
  end

  # AJAX call
  def get_school_users_list
    # Get lists of organisation owners and school admins (DNs)
    organisation_owners = Array(LdapOrganisation.current.owner)
                          .reject { |dn| dn == 'uid=admin,o=puavo' }
                          .collect { |o| o.to_s }

    organisation_owners = Array(organisation_owners || []).to_set

    school_admins = Array(@school.user_school_admins || []).collect { |a| a.dn.to_s }.to_set

    schools_by_dn = {}

    School.search_as_utf8(:filter => '',
                          :attributes => ['cn', 'displayName', 'puavoId']).each do |dn, school|
      schools_by_dn[dn] = {
        id: school['puavoId'][0].to_i,
        cn: school['cn'][0],
        name: school['displayName'][0].force_encoding('utf-8'),
      }
    end

    krb_auth_times_by_uid = Kerberos.all_auth_times_by_uid

    # Get a raw list of users in this school
    raw = User.search_as_utf8(:filter => "(puavoSchool=#{@school.dn})",
                              :scope => :one,
                              :attributes => UsersHelper.get_user_attributes())

    # Build a list of devices whose primary users are in this school. If the viewer is a school
    # admin and the device is in a school they don't have access to, then ACLs will prevent the
    # device search below from seeing the device.
    puavoid_extractor = /puavoId=([^, ]+)/.freeze

    users_devices = {}

    raaka = Device.search_as_utf8(
      filter: "(puavoDevicePrimaryUser=*)",
      scope: :one,
      attributes: ['puavoDevicePrimaryUser', 'puavoHostname', 'puavoSchool']
    ).each do |device_dn, raw_device|
      # PuavoIDs for manual link formatting (manual is faster than automatic)
      device_id = device_dn.match(puavoid_extractor)[1].to_i
      device_school_id = raw_device['puavoSchool'][0].match(puavoid_extractor)[1].to_i

      user_dn = raw_device['puavoDevicePrimaryUser'][0]
      users_devices[user_dn] ||= []

      users_devices[user_dn] << [
        raw_device['puavoHostname'][0],
        "/devices/#{device_school_id}/devices/#{device_id}",
        device_school_id
      ]
    end

    # Convert the raw data into something we can easily parse in JavaScript
    school_id = @school.id.to_i
    users = []

    raw.each do |dn, usr|
      # Common attributes
      user = UsersHelper.convert_raw_user(dn, usr, organisation_owners, school_admins)

      # Special attributes
      user[:link] = "/users/#{school.id}/users/#{user[:id]}"
      user[:school_id] = school_id
      user[:schools] = Array(usr['puavoSchool'].map { |dn| schools_by_dn[dn][:id] }) - [school_id]
      user[:devices] = users_devices[dn] if users_devices.include?(dn)

      krb_auth_date = Integer(krb_auth_times_by_uid[ user[:uid] ] \
                        .to_date.to_time) rescue nil
      user[:last_kerberos_auth_date] = krb_auth_date if krb_auth_date

      users << user
    end

    render :json => users
  end

  # GET /:school_id/users/1/image
  def image
    @user = User.find(params[:id])

    send_data @user.jpegPhoto, :disposition => 'inline', :type => "image/jpeg"
  end

  # GET /:school_id/users/1
  # GET /:school_id/users/1.xml
  def show
    @user = get_user(params[:id])
    return if @user.nil?

    # get the creation, modification and last authentication timestamps from
    # LDAP operational attributes
    extra = User.find(params[:id], :attributes => ['authTimestamp', 'createTimestamp', 'modifyTimestamp'])
    @user['authTimestamp']   = convert_timestamp_pick_date(extra['authTimestamp']) if extra['authTimestamp']
    @user['createTimestamp'] = convert_timestamp(extra['createTimestamp'])
    @user['modifyTimestamp'] = convert_timestamp(extra['modifyTimestamp'])

    @user.kerberos_last_successful_auth \
      = @user.kerberos_last_successful_auth_utc ? convert_timestamp_pick_date(@user.kerberos_last_successful_auth_utc) : nil

    if @user.puavoRemovalRequestTime
      @user.puavoRemovalRequestTime = convert_timestamp(@user.puavoRemovalRequestTime)
    end

    # Is the user an organisation owner?
    organisation_owners = Array(LdapOrganisation.current.owner).each.select { |dn| dn != "uid=admin,o=puavo" } || []
    @user_is_owner = organisation_owners.include?(@user.dn)

    @viewer_is_an_owner = is_owner?
    viewer_is_admin_in = Array(current_user.puavoAdminOfSchool || []).map(&:to_s).to_set

    # List schools where this user is an admin in
    @admin_in_schools = []

    Array(@user.puavoAdminOfSchool || []).each do |dn|
      begin
        @admin_in_schools << School.find(dn)
      rescue StandardError => e
        logger.error "Unable to find admin school by DN \"#{dn.to_s}\": #{e}"
      end
    end

    @admin_in_schools.sort! { |a, b| a.displayName.downcase <=> b.displayName.downcase }

    # If the user is a member in more than one school, list them all in alphabetical order
    primary_school = @user.primary_school
    @primary_school_dn = primary_school.dn

    if Array(@user.school).count > 1
      @user_schools = Array(@user.school).sort{ |a, b| a.displayName.downcase <=> b.displayName.downcase }
    else
      @user_schools = []
    end

    # List of systems where user deletions are synchronised. We only care about synchronised
    # deletions in the primary school. Multi-school sync deletions will be implemented later...
    school_id = primary_school.id.to_i
    @synchronised_deletions = {}
    deletions = list_school_synchronised_deletion_systems(@organisation_name, school_id)

    unless deletions.empty?
      @synchronised_deletions[school_id] = deletions.to_a.sort
    end

    # find the user's devices
    @user_devices = Device.find(:all,
                                :attribute => "puavoDevicePrimaryUser",
                                :value => @user.dn.to_s)

    # group user's groups by school
    by_school_hash = {}

    Array(@user.groups || []).each do |group|
      unless by_school_hash.include?(group.school.dn)
        by_school_hash[group.school.dn] = {
          school: group.school,
          accessible: @viewer_is_an_owner ? true : viewer_is_admin_in.include?(group.school.dn.to_s),
          groups: []
        }
      end

      by_school_hash[group.school.dn][:groups] << group
    end

    # flatten the hash and sort the schools by name
    @user_groups = []

    by_school_hash.each { |_, data| @user_groups << data }
    @user_groups.sort! { |a, b| a[:school].displayName.downcase <=> b[:school].displayName.downcase }

    # then sort the per-school group lists by name
    @user_groups.each do |data|
      data[:groups].sort! { |a, b| a.displayName.downcase <=> b.displayName.downcase }
    end

    @own_page = current_user.id == @user.id

    @permit_user_deletion = @viewer_is_an_owner || current_user.has_admin_permission?(:delete_users)

    # External data fields
    @mpass_materials_charge = nil

    if @user.puavoExternalData
      begin
        ed = JSON.parse(@user.puavoExternalData)

        if @user.puavoEduPersonAffiliation.include?('student')
          @mpass_materials_charge = ed.fetch('materials_charge', nil)
        end
      rescue
      end
    end

    # What actions have been granted for this admin?
    @admin_permissions = []

    unless @user_is_owner
      if Array(@user.puavoEduPersonAffiliation || []).include?('admin')
        User::ADMIN_PERMISSIONS.each do |permission|
          if @user.has_admin_permission?(permission)
            @admin_permissions << permission
          end
        end
      end
    end

    # Does this organisation have any SSO sessions enabled? We don't care what services
    # they're enabled for, as long as there's at least one.
    organisation = Puavo::Organisation.find(LdapOrganisation.current.cn)
    @have_sso_sessions = organisation && !organisation.value_by_key('enable_sso_sessions_in').nil?

    # Look up verified email addresses
    @verified_addresses = Array(@user.puavoVerifiedEmail || []).to_set.freeze
    @emails = []

    Array(@user.mail || []).each do |addr|
      parts = []

      parts << 'verified' if @verified_addresses.include?(addr)
      parts << 'primary' if @user.puavoPrimaryEmail == addr

      @emails << [addr, parts]
    end

    # Highlight invalid license data
    @licenses_ok = true
    @licenses = nil

    begin
      @licenses = JSON.parse(@user.puavoLicenses) if @user.puavoLicenses
    rescue StandardError => e
      @licenses_ok = false
      @licenses = @user.puavoLicenses.to_s
    end

    respond_to do |format|
      format.html # show.html.erb
      format.xml  { render :xml => @user }
      # FIXME, remove user key?
      format.json  { render :json => @user  }
    end
  end

  def setup_integrations_for_form(school, is_new_user)
    @is_admin_school = school.displayName == 'Administration'
    @have_primus = false
    @have_gsuite = false
    @pw_warning = :none
    @needs_password_validator = false

    unless @is_admin_school
      # Administration schools NEVER show/have any integrations, even if someone
      # defines them.
      @have_primus = school_has_integration?(@organisation_name, school.id, 'primus')
      @have_gsuite = school_has_integration?(@organisation_name, school.id, 'gsuite')

      if school_has_sync_actions_for?(@organisation_name, school.id, :change_password)
        if is_new_user
          @pw_warning = :new
        else
          @pw_warning = :edit
        end
      end
    end

  end

  # GET /:school_id/users/new
  # GET /:school_id/users/new.xml
  def new
    unless is_owner? || current_user.has_admin_permission?(:create_users)
      flash[:alert] = t('flash.you_must_be_an_owner')
      redirect_to users_path
      return
    end

    @user = User.new
    @groups = @school.groups

    @edu_person_affiliation = @user.puavoEduPersonAffiliation || []

    @automatic_email_addresses, @automatic_email_domain = get_automatic_email_addresses

    @is_new_user = true
    setup_integrations_for_form(@school, true)

    get_group_list

    respond_to do |format|
      format.html # new.html.erb
      format.xml  { render :xml => @user }
    end
  end

  # GET /:school_id/users/1/edit
  def edit
    @user = get_user(params[:id])
    return if @user.nil?

    @edu_person_affiliation = @user.puavoEduPersonAffiliation || []

    @automatic_email_addresses, @automatic_email_domain = get_automatic_email_addresses

    @is_new_user = false
    setup_integrations_for_form(@school, false)

    get_group_list
  end

  # POST /:school_id/users
  # POST /:school_id/users.xml
  def create
    unless is_owner? || current_user.has_admin_permission?(:create_users)
      flash[:alert] = t('flash.you_must_be_an_owner')
      redirect_to users_path
      return
    end

    @user = User.new(user_params)
    @groups = @school.groups

    # Automatically generate the email address
    @automatic_email_addresses, @automatic_email_domain = get_automatic_email_addresses

    if @automatic_email_addresses
      @user.mail = "#{@user.uid.strip}@#{@automatic_email_domain}"
    end

    # TODO: should we use the filtered hash returned by "user_params" here
    # instead of modifying the raw unfiltered "params" object?
    params[:user][:puavoEduPersonAffiliation] ||= []
    @edu_person_affiliation = params[:user][:puavoEduPersonAffiliation]

    @user.puavoSchool = @school.dn
    @user.puavoEduPersonPrimarySchool = @school.dn

    @is_new_user = true
    setup_integrations_for_form(@school, true)

    respond_to do |format|
      begin
        unless @user.save
          raise UserError, I18n.t('flash.user.create_failed')
        end

        # Add to groups
        if params.include?(:groups)
          update_user_groups(@user, params[:groups])
        end

        format.html { redirect_to( user_path(@school, @user) ) }
        format.json { render :json => nil }
      rescue UserError => e
        logger.info "Create user, Exception: " + e.to_s
        get_group_list
        error_message_and_render(format, 'new', e.message)
      end
    end
  end

  # PUT /:school_id/users/1
  # PUT /:school_id/users/1.xml
  def update
    @user = get_user(params[:id])
    return if @user.nil?

    @groups = @school.groups

    params[:user][:puavoEduPersonAffiliation] ||= []
    @edu_person_affiliation = params[:user][:puavoEduPersonAffiliation]

    @is_new_user = false
    setup_integrations_for_form(@school, false)

    if @user.puavoDoNotDelete && params[:user].include?('puavoLocked')
      # Undeletable users cannot be locked, ever
      params[:user]['puavoLocked'] = false
    end

    respond_to do |format|
      begin

        if current_user.id == @user.id &&
           params[:user].include?('puavoLocked') &&
           params[:user]['puavoLocked'] == '1'
          raise UserError, I18n.t('flash.user.you_cant_lock_yourself')
        end

        # Detect admin role changes
        was_admin = @user.puavoEduPersonAffiliation.include?("admin")
        is_admin = @edu_person_affiliation.include?("admin")

        if was_admin && !is_admin
          # This user used to be an admin. If they were a school admin or an organisation owner
          # we must remove them from those lists.

          # Copy-pasted from the "destroy" method below
          organisation_owners = Array(LdapOrganisation.current.owner).each.select { |dn| dn != "uid=admin,o=puavo" }

          if organisation_owners && organisation_owners.include?(@user.dn)
            begin
              LdapOrganisation.current.remove_owner(@user)
            rescue StandardError => e
              logger.error e
              raise UserError, I18n.t('flash.user.save_failed_organsation_owner_removal')
            end
          end

          # Remove the user from school admins. Turns out you can be an admin on multiple schools,
          # so have to loop.
          School.all.each do |s|
            school_admins = s.user_school_admins

            if school_admins && school_admins.include?(@user)
              # Copy-pasted and modified from school.rb, method remove_school_admin()
              # There's no standalone method for this (or I can't find it)
              begin
                if Array(@user.puavoAdminOfSchool).count < 2
                  SambaGroup.delete_uid_from_memberUid('Domain Admins', @user.uid)
                end

                begin
                  s.ldap_modify_operation(:delete, [{"puavoSchoolAdmin" => [@user.dn.to_s]}])
                rescue ActiveLdap::LdapError::NoSuchAttribute
                end

                begin
                  @user.ldap_modify_operation(:delete, [{"puavoAdminOfSchool" => [s.dn.to_s]}])
                rescue ActiveLdap::LdapError::NoSuchAttribute
                end
              rescue StandardError => e
                raise UserError, I18n.t('flash.user.save_failed_school_admin_removal')
              end
            end
          end

          # Clear admin permissions
          @user.puavoAdminPermissions = nil
        end

        up = user_params()

        # Automatically update the email address. We have to manipulate the user_params
        # array, because the actual update logic happens inside @user.update_attributes()
        # and we can't easily change it (the base method comes from the activeldap gem).
        # So instead simulate the email address field being edited.
        @automatic_email_addresses, @automatic_email_domain = get_automatic_email_addresses

        if @automatic_email_addresses
          up['mail'] = ["#{up['uid'].strip}@#{@automatic_email_domain}"]
        else
          removed = Array(@user.puavoVerifiedEmail) - up['mail']

          unless removed.empty?
            # One or more verified addresses are missing. Put them back;
            # they're not supposed to be removed.
            up['mail'] += removed
          end

          # Clean up the address array in the same way puavo-rest does it
          up['mail'] = up['mail']
            .compact                  # remove nil values
            .map { |e| e.strip }      # remove trailing and leading whitespace
            .reject { |e| e.empty? }  # remove completely empty strings
            .uniq                     # remove duplicates
        end

        unless @user.update_attributes(up)
          raise UserError, I18n.t('flash.user.save_failed')
        end

        # Update all group associations
        update_user_groups(@user, params[:groups] || [])

        # Save new password to session otherwise next request does not work
        if session[:dn] == @user.dn
          unless params[:user][:new_password].nil? || params[:user][:new_password].empty?
            session[:password_plaintext] = params[:user][:new_password]
          end
        end
        flash[:notice] = t('flash.updated', :item => t('activeldap.models.user'))
        format.html { redirect_to( user_path(@school,@user) ) }
      rescue UserError => e
        get_group_list
        error_message_and_render(format, 'edit',  e.message)
      end
    end
  end

  # DELETE /:school_id/users/1
  # DELETE /:school_id/users/1.xml
  def destroy
    # Can't use redirected_nonowner_user? here because we must allow school admins
    # to get here too if it has been explicitly allowed
    unless is_owner? || current_user.has_admin_permission?(:delete_users)
      flash[:alert] = t('flash.you_must_be_an_owner')
      redirect_to users_path
      return
    end

    @user = get_user(params[:id])
    return if @user.nil?

    if current_user.id == @user.id
      flash[:alert] = t('flash.user.cant_delete_yourself')
    elsif @user.puavoDoNotDelete
      flash[:alert] = t('flash.user_deletion_prevented')
    else
      # Remove the user from external systems first
      status, message = delete_user_from_external_systems(@user)

      unless status
        # failed, stop here
        flash[:alert] = message
        redirect_to(users_url)
        return
      end

      if @user.puavoEduPersonAffiliation && @user.puavoEduPersonAffiliation.include?('admin')
        # if an admin user is also an organisation owner, remove the ownership
        # automatically before deletion
        owners = Array(LdapOrganisation.current.owner).each.select { |dn| dn != "uid=admin,o=puavo" }.map{ |o| o.to_s }

        if owners && owners.include?(@user.dn.to_s)
          if !LdapOrganisation.current.remove_owner(@user)
            flash[:alert] = t('flash.organisation_ownership_not_removed')
          else
            # TODO: Show a flash message when ownership is removed. First we need to
            # support multiple flash messages of the same type...
            #flash[:notice] = t('flash.organisation_ownership_removed')
          end
        end
      end

      # LDAP is not a relational database, so if this user was the primary user of any devices,
      # we must manually break those connections.
      begin
        DevicesHelper.clear_device_primary_user(@user.dn)
      rescue StandardError => e
        # At least one device failed, CANCEL the opeation to avoid dangling references
        logger.info("Failed to clear the primary user of a device: #{e}")
        flash[:alert] = t('flash.device_primary_user_removal_failed')
        redirect_to(user_path(@school, @user))
        return
      end

      if @user.destroy
        flash[:notice] = t('flash.destroyed', :item => t('activeldap.models.user'))
      end
    end

    respond_to do |format|
      format.html { redirect_to(users_url) }
      format.xml  { head :ok }
    end
  end

  def request_password_reset
    return if redirected_nonowner_user?

    @user = get_user(params[:id])
    return if @user.nil?

    request_id = generate_synchronous_call_id()

    if @user.mail.nil? || @user.mail.empty?
      flash[:alert] = t('flash.user.reset_failed_no_emails', request_id: request_id)
    else
      if @user.puavoPrimaryEmail
        address = @user.puavoPrimaryEmail
      else
        address = Array(@user.mail).first
      end

      begin
        logger.info("[#{request_id}] Sending a password reset email for user \"#{@user.uid}\" (#{@user.dn.to_s}) to address \"#{address}\"")
        ret = Puavo::Password::send_password_reset_mail(logger, LdapOrganisation.first.puavoDomain, password_management_host, locale, request_id, address)

        case ret
          when :ok
            flash[:notice] = t('flash.user.reset_email_sent')

          when :user_not_found
            flash[:alert] = t('flash.user.reset_failed_user_not_found', request_id: request_id)

          when :link_already_sent
            flash[:alert] = t('flash.user.reset_failed_link_already_sent', request_id: request_id)

          when :link_sending_failed
            flash[:alert] = t('flash.user.reset_failed_link_sending_failed', request_id: request_id)

          when :puavo_rest_call_failed
            flash[:alert] = t('flash.user.reset_failed_puavo_rest_call_failed', request_id: request_id)
        end
      rescue => e
        logger.error("[#{request_id}] Password reset failed: #{e}")
        flash[:alert] = t('flash.user.reset_failed_generic', request_id: request_id)
      end
    end

    respond_to do |format|
      format.html { redirect_to(user_path(@school, @user)) }
    end
  end

  def reset_sso_session
    return if redirected_nonowner_user?

    @user = get_user(params[:id])
    return if @user.nil?

    @user.reset_sso_session
    flash[:notice] = t('flash.user.sso_session_gone')

    respond_to do |format|
      format.html { redirect_to(user_path(@school, @user)) }
    end
  end

  def change_schools
    return if redirected_nonowner_user?

    @user = get_user(params[:id])
    return if @user.nil?

    @primary_school = @user.primary_school
    @primary_school_dn = @primary_school.dn

    @current_schools = []
    current_dns = Set.new

    # TODO: reuse the user.school array here instead of finding new instances?
    Array(@user.puavoSchool).each do |dn|
      s = School.find(dn)
      @current_schools << s
      current_dns << s.dn.to_s
    end

    @available_schools = School.all.reject{ |s| current_dns.include?(s.dn.to_s) }

    @admin_in_schools = Array(@user.puavoAdminOfSchool).map{ |dn| dn.to_s }.to_set

    # As the underlying (LDAP) arrays have no order (that we can trust), we can sort
    # these nicely. The only thing that matters is the primary school's DN.
    @current_schools.sort!{ |a, b| a.displayName.downcase <=> b.displayName.downcase }
    @available_schools.sort!{ |a, b| a.displayName.downcase <=> b.displayName.downcase }
  end

  def add_to_school
    return if redirected_nonowner_user?

    @user = get_user(params[:id])
    return if @user.nil?

    begin
      unless @user.puavoEduPersonPrimarySchool
        # This user has currently one school (at least we hope so!), so
        # make it the primary school before adding another school
        @user.puavoEduPersonPrimarySchool = @user.primary_school.dn
      end

      @target = School.find(params[:school])
      @user.puavoSchool = Array(@user.puavoSchool) + [@target.dn]
      @user.save!

      flash[:notice] = t('flash.user.added_to_school', :name => @target.displayName)
    rescue StandardError => e
      logger.error('-' * 50)
      logger.error(e)
      logger.error('-' * 50)
      flash[:alert] = t('flash.user.school_adding_failed')
    end

    redirect_to(change_schools_path(@user.primary_school, @user))
  end

  def remove_from_school
    return if redirected_nonowner_user?

    @user = get_user(params[:id])
    return if @user.nil?

    begin
      @target = School.find(params[:school])

      if @user.puavoEduPersonPrimarySchool == @target.dn
        # The UI won't let you do this, but let's check for it anyway before creating a disaster
        flash[:alert] = t('flash.user.cannot_remove_primary_school')
        redirect_to(change_schools_path(@user.primary_school, @user))
        return
      end

      Puavo::UsersShared::remove_user_from_school(@user, @target)

      flash[:notice] = t('flash.user.removed_from_school', :name => @target.displayName)
    rescue StandardError => e
      logger.error('-' * 50)
      logger.error(e)
      logger.error('-' * 50)
      flash[:alert] = t('flash.user.school_removing_failed')
    end

    redirect_to(change_schools_path(@user.primary_school, @user))
  end

  def set_primary_school
    return if redirected_nonowner_user?

    @user = get_user(params[:id])
    return if @user.nil?

    begin
      @target = School.find(params[:school])

      # This can only be done if the user already is in the target school.
      # The UI won't let you do this, but let's verify it.
      unless Array(@user.puavoSchool).include?(@target.dn)
        flash[:alert] = t('flash.user.invalid_primary_school', :name => @target.displayName)
        redirect_to(change_schools_path(@user.primary_school, @user))
        return
      end

      @user.puavoEduPersonPrimarySchool = @target.dn
      @user.save!

      flash[:notice] = t('flash.user.primary_school_changed', :name => @target.displayName)
    rescue StandardError => e
      logger.error('-' * 50)
      logger.error(e)
      logger.error('-' * 50)
      flash[:alert] = t('flash.user.primary_school_change_failed')
    end

    redirect_to(change_schools_path(@user.primary_school, @user))
  end

  def add_and_set_primary_school
    return if redirected_nonowner_user?

    @user = get_user(params[:id])
    return if @user.nil?

    begin
      @target = School.find(params[:school])

      schools = Array(@user.puavoSchool.dup)
      schools << @target.dn
      @user.puavoSchool = (schools.count == 1) ? schools[0] : schools
      @user.puavoEduPersonPrimarySchool = @target.dn
      @user.save!

      flash[:notice] = t('flash.user.primary_school_added_and_changed', :name => @target.displayName)
    rescue StandardError => e
      logger.error('-' * 50)
      logger.error(e)
      logger.error('-' * 50)
      flash[:alert] = t('flash.user.primary_school_add_and_change_failed')
    end

    redirect_to(change_schools_path(@user.primary_school, @user))
  end

  def move_to_school
    return if redirected_nonowner_user?

    @user = get_user(params[:id])
    return if @user.nil?

    begin
      @previous = @user.primary_school
      @target = School.find(params[:school])

      # Remove school admin associations if needed
      Array(@user.puavoAdminOfSchool).each do |dn|
        if dn.to_s == @previous.dn.to_s
          @user.puavoAdminOfSchool = Array(@user.puavoAdminOfSchool).reject{ |dn| dn.to_s == @previous.dn.to_s }
          @previous.puavoSchoolAdmin = Array(@previous.puavoSchoolAdmin).reject{ |dn| dn.to_s == @user.dn.to_s }
          @previous.save!
          break
        end
      end

      # This change must be done in two steps. Something somewhere gets cached and the
      # school won't change and @user.save! will fail if we do everything in one step.
      # Or maybe I was just doing it incorrectly?

      # Add the new school
      schools = Array(@user.puavoSchool.dup)
      schools << @target.dn
      @user.puavoSchool = (schools.count == 1) ? schools[0] : schools
      @user.save!

      # Then swap the primary school and remove the old school
      @user = get_user(params[:id])
      @user.puavoSchool = @target.dn
      @user.puavoEduPersonPrimarySchool = @target.dn
      @user.save!

      # The system appears to automatically add the user's UID and DN to the relevant arrays,
      # but it won't *remove* them
      begin
        LdapBase.ldap_modify_operation(@previous.dn, :delete, [{ "member" => [@user.dn.to_s] }])
      rescue ActiveLdap::LdapError::NoSuchAttribute
      end

      begin
        LdapBase.ldap_modify_operation(@previous.dn, :delete, [{ "memberUid" => [@user.uid.to_s] }])
      rescue ActiveLdap::LdapError::NoSuchAttribute
      end

      flash[:notice] = t('flash.user.user_moved_to_school', :name => @target.displayName)
    rescue StandardError => e
      logger.error('-' * 50)
      logger.error(e)
      logger.error('-' * 50)
      flash[:alert] = t('flash.user.school_moving_failed')
    end

    redirect_to(change_schools_path(@user.primary_school, @user))
  end

  def username_redirect
    user = User.find(:first, :attribute => "uid", :value => params["username"])
    if user.nil?
      return render :plain => "Unknown user #{ ActionController::Base.helpers.sanitize(params["username"]) }", :status => 400
    end
    redirect_to user_path(params["school_id"], user.id)
  end

  # GET /:school_id/users/:id/edit_admin_permissions
  def edit_admin_permissions
    @user = User.find(params[:id])

    unless is_owner?
      flash[:alert] = t('flash.you_must_be_an_owner')
      redirect_to(user_path(@school, @user))
      return
    end

    # Prevent direct URL manipulation
    unless Array(@user.puavoEduPersonAffiliation).include?('admin')
      flash[:alert] = t('flash.user.not_an_admin')
      redirect_to(user_path(@school, @user))
      return
    end

    @current_permissions = Array(@user.puavoAdminPermissions).to_set.freeze

    @user_is_owner = Array(LdapOrganisation.current.owner).include?(@user.dn)

    respond_to do |format|
      format.html
    end
  end

  # POST /:school_id/users/:id/edit_admin_permissions
  def save_admin_permissions
    @user = User.find(params[:id])

    begin
      unless is_owner?
        flash[:alert] = t('flash.you_must_be_an_owner')
      else
        # Ensure no incorrect permissions can get through
        permissions = params.fetch('permissions', []).dup

        @user.puavoAdminPermissions = permissions.select { |p| User::ADMIN_PERMISSIONS.include?(p.to_sym) }
        @user.save!

        flash[:notice] = t('flash.user.admin_permissions_updated')
      end
    rescue StandardError => e
      logger.error("Failed to save the admin permissions: #{e}")
      flash[:alert] = t('flash.save_failed')
    end

    redirect_to(user_path(@school, @user))
  end

  def lock
    @user = User.find(params[:id])

    if current_user.id == @user.id
      flash[:alert] = t('flash.user.you_cant_lock_yourself')
    else
      @user.puavoLocked = true
      @user.save
      flash[:notice] = t('flash.user.locked')
    end

    respond_to do |format|
      format.html { redirect_to(user_path(@school, @user)) }
    end
  end

  def unlock
    @user = User.find(params[:id])

    @user.puavoLocked = false
    @user.save
    flash[:notice] = t('flash.user.unlocked')

    respond_to do |format|
      format.html { redirect_to(user_path(@school, @user)) }
    end
  end

  def mark_for_deletion
    @user = User.find(params[:id])

    if current_user.id == @user.id
      flash[:alert] = t('flash.user.cant_mark_yourself_for_deletion')
    elsif @user.puavoDoNotDelete
      flash[:alert] = t('flash.user_deletion_prevented')
    else
      if @user.puavoRemovalRequestTime.nil?
        @user.puavoRemovalRequestTime = Time.now.utc
        @user.puavoLocked = true
        @user.save
        flash[:notice] = t('flash.user.marked_for_deletion')
      else
        flash[:alert] = t('flash.user.already_marked_for_deletion')
      end
    end

    respond_to do |format|
      format.html { redirect_to( user_path(@school, @user) ) }
    end
  end

  def unmark_for_deletion
    @user = User.find(params[:id])

    if @user.puavoRemovalRequestTime
      @user.puavoRemovalRequestTime = nil
      @user.save
      flash[:notice] = t('flash.user.unmarked_for_deletion')
    else
      flash[:alert] = t('flash.user.not_marked_for_deletion')
    end

    respond_to do |format|
      format.html { redirect_to( user_path(@school, @user) ) }
    end
  end

  def prevent_deletion
    return if redirected_nonowner_user?

    @user = User.find(params[:id])

    @user.puavoDoNotDelete = true
    @user.puavoRemovalRequestTime = nil
    @user.puavoLocked = false   # can't be locked if they cannot be deleted
    @user.save

    flash[:notice] = t('flash.user.deletion_prevented')

    respond_to do |format|
      format.html { redirect_to( user_path(@school, @user) ) }
    end
  end

  private

  def error_message_and_render(format, action, message = nil)
    flash[:alert] = message unless message.nil?

    format.html { render :action => action }
    format.xml  { render :xml => @user.errors, :status => :unprocessable_entity }
  end

  def get_group_list
    @is_owner = is_owner?

    unless @is_owner
      # Don't show groups in schools that this user can't access
      school_filter = Array(current_user.puavoAdminOfSchool || []).map(&:to_s).to_set
    end

    # Partition groups by school. This has to be done with raw searches. Writing
    # "Group.all" is so easy, but so slow... multiple minutes slow in some places.
    school_names = {}

    School.search_as_utf8(:filter => '', :attributes => ['displayName']).each do |dn, school|
      school_names[dn] = school['displayName'][0]
    end

    # Don't repeatedly call t() when listing potentiall hundreds of groups
    group_types = {
      nil => nil,
      'teaching group' => t('group_type.teaching group'),
      'course group' => t('group_type.course group'),
      'year class' => t('group_type.year class'),
      'administrative group' => t('group_type.administrative group'),
      'archive users' => t('group_type.archive users'),
      'other groups' => t('group_type.other groups'),
    }

    @groups_by_school = {}

    group_attrs = ['puavoId', 'displayName', 'puavoEduGroupType', 'puavoSchool', 'member']

    Group.search_as_utf8(filter: '(objectClass=puavoEduGroup)', attributes: group_attrs).each do |dn, g|
      school_dn = g['puavoSchool'][0]

      next if !@is_owner && !school_filter.include?(school_dn)

      school_name_sort = school_names[school_dn].downcase

      @groups_by_school[school_dn] ||= {
        school_name: school_names[school_dn],
        school_name_sort: school_name_sort,
        groups: []
      }

      @groups_by_school[school_dn][:groups] << {
        id: g['puavoId'][0].to_i,
        name: g['displayName'][0],
        name_sort: "#{school_name_sort} #{g['displayName'][0].downcase}",
        type: group_types[g.fetch('puavoEduGroupType', [nil])[0]],
        member_dn: Array(g['member'] || []).to_set,
      }
    end

    # Sort the groups by name
    @groups_by_school.each do |_, school|
      school[:groups].sort! { |a, b| a[:name_sort] <=> b[:name_sort] }
    end

    # Sort the schools by name
    @groups_by_school = @groups_by_school.values
    @groups_by_school.sort! { |a, b| a[:school_name_sort] <=> b[:school_name_sort] }
  end

    def update_user_groups(user, new_group_ids)
      return if user.nil?

      # Access control. The group list on the page won't include groups in schools
      # non-owners can't access, but do another level of checks here, in case
      # something fails. This also protects against the cases where a non-owner
      # user knows the IDs of the "invisible" groups and manually edits the page
      # to include those group IDs. At least that's the idea here. Never trust
      # user input.
      is_owner = is_owner?
      only_these = Array(current_user.puavoAdminOfSchool || []).map(&:to_s).to_set

      # Figure out what has changed
      current_groups = Array(user.groups || []).collect { |g| g.puavoId.to_i }.to_set
      new_groups = new_group_ids.map(&:to_i).to_set

      remove_groups = current_groups - new_groups
      add_groups = new_groups - current_groups

      # Then apply the changes
      remove_groups.each do |id|
        g = Group.find(id)

        next if !is_owner && !only_these.include?(g.school.dn.to_s)
        g.remove_user(user)
      end

      add_groups.each do |id|
        g = Group.find(id)

        next if !is_owner && !only_these.include?(g.school.dn.to_s)
        g.add_user(user)
      end
    end

    def user_params
      u = params.require(:user).permit(
          :givenName,
          :sn,
          :uid,
          :puavoLocale,
          :puavoAllowRemoteAccess,
          :puavoEduPersonPersonnelNumber,
          :image,
          :puavoLocked,
          :puavoSshPublicKey,
          :puavoExternalId,
          :puavoNotes,
          :new_password,
          :new_password_confirmation,
          :mail=>[],
          :telephoneNumber=>[],
          :puavoEduPersonAffiliation=>[]).to_hash

      # deduplicate arrays, as LDAP really does not like duplicate entries...
      u["mail"].uniq! if u.key?("mail")
      u["telephoneNumber"].uniq! if u.key?("telephoneNumber")

      return u
    end

    def get_user(id)
      begin
        return User.find(id)
      rescue ActiveLdap::EntryNotFound => e
        flash[:alert] = t('flash.invalid_user_id', :id => id)
        redirect_to users_path(@school)
        return nil
      end
    end
end
