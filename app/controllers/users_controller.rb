class UsersController < ApplicationController
  include Puavo::Integrations
  include Puavo::MassOperations

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
                  'homeDirectory',
                  'mail',
                  'puavoEduPersonReverseDisplayName',
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

    respond_to do |format|
      format.html # index.html.erb
      format.xml  { render :xml => @users }
      format.json { render :json => @users }
    end
  end

  # New AJAX-based index for non-test environments
  def new_cool_users_index
    @is_owner = is_owner?
    @permit_single_user_deletion = false
    @permit_single_user_creation = false

    unless @is_owner
      # This user is not an owner, but they *have* to be a school admin, because only owners
      # and school admins can log in. See if they've been granted any extra permissions.
      if can_schooladmin_do_this?(current_user.uid, :delete_single_users)
        @permit_single_user_deletion = true
      end

      if can_schooladmin_do_this?(current_user.uid, :create_single_users)
        @permit_single_user_creation = true
      end
    else
      # Owners can always create and delete users
      @permit_single_user_creation = true
      @permit_single_user_deletion = true
    end

    @automatic_email_addresses, _ = get_automatic_email_addresses

    # List of systems where user deletions are synchronised
    @synchronised_deletions = {}
    deletions = list_school_synchronised_deletion_systems(@organisation_name, school.id.to_i)

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

    # Get a raw list of users in this school
    raw = User.search_as_utf8(:filter => "(puavoSchool=#{@school.dn})",
                              :scope => :one,
                              :attributes => UsersHelper.get_user_attributes())

    # Convert the raw data into something we can easily parse in JavaScript
    school_id = @school.id.to_i
    users = []

    raw.each do |dn, usr|
      # Common attributes
      user = UsersHelper.convert_raw_user(dn, usr, organisation_owners, school_admins)

      # Special attributes
      user[:link] = "/users/#{school.id}/users/#{user[:id]}"
      user[:school_id] = school_id

      users << user
    end

    render :json => users
  end

  # ------------------------------------------------------------------------------------------------
  # ------------------------------------------------------------------------------------------------

  # Mass operation: delete user
  def mass_op_user_delete
    begin
      user_id = params[:user][:id]
    rescue
      puts "mass_op_user_delete(): missing required params in the request:"
      puts params.inspect
      return status_failed_msg('mass_op_user_delete(): missing params')
    end

    ok = false

    begin
      user = User.find(user_id)

      if user.puavoDoNotDelete
        return status_failed_trans('users.index.mass_operations.delete.deletion_prevented')
      end

      unless user.puavoRemovalRequestTime
        return status_failed_trans('users.index.mass_operations.delete.not_marked_for_deletion')
      end

      if user.puavoRemovalRequestTime + 7.days > Time.now.utc
        return status_failed_trans('users.index.mass_operations.delete.marked_too_recently')
      end

      # Remove the user from external systems first, stop if this fails
      status, message = delete_user_from_external_systems(user, plaintext_message: true)

      unless status
        return status_failed_msg(message)
      end

      user.delete
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

  # Mass operation: lock/unlock user
  def mass_op_user_lock
    begin
      user_id = params[:user][:id]
      lock = params[:user][:lock]
    rescue
      puts "mass_op_user_lock(): missing required params in the request:"
      puts params.inspect
      return status_failed_msg('mass_op_user_lock(): missing params')
    end

    ok = false

    begin
      user = User.find(user_id)

      if user.puavoLocked && !lock
        user.puavoLocked = false
        user.save!
      elsif !user.puavoLocked && lock
        user.puavoLocked = true
        user.save!
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

  # Mass operation: mark/unmark for later deletion
  def mass_op_user_mark
    begin
      user_id = params[:user][:id]
      operation = params[:user][:operation]
    rescue
      puts "mass_op_user_mark(): missing required params in the request:"
      puts params.inspect
      return status_failed_msg('mass_op_user_mark(): missing params')
    end

    ok = false

    begin
      user = User.find(user_id)

      if operation == 0
        # Lock
        if user.puavoDoNotDelete
          return status_failed_trans('users.mass_operations.delete.deletion_prevented')
        end

        if user.puavoRemovalRequestTime
          # already marked for deletion, do nothing
          ok = true
        else
          user.puavoRemovalRequestTime = Time.now.utc
          user.puavoLocked = true
          user.save!
          ok = true
        end
      elsif operation == 1
        # Force lock (resets locking timestamp)
        if user.puavoDoNotDelete
          return status_failed_trans('users.mass_operations.delete.deletion_prevented')
        end

        # always overwrite the existing timestamp
        user.puavoRemovalRequestTime = Time.now.utc
        user.puavoLocked = true
        user.save!
        ok = true
      else
        # Unlock
        if user.puavoRemovalRequestTime
          user.puavoRemovalRequestTime = nil
          user.puavoLocked = false
          user.save!
        end

        ok = true
      end
    rescue StandardError => e
      return status_failed_msg(e)
    end

    if ok
      return status_ok()
    else
      return status_failed_msg('unknown_error')
    end
  end

  # Mass operation: clear column (their values must be unique, so setting them
  # to anything except empty is pointless)
  def mass_op_user_clear_column
    begin
      user_id = params[:user][:id]
      column = params[:user][:column]
    rescue
      puts "mass_op_user_clear_column(): missing required params in the request:"
      puts params.inspect
      return status_failed_msg('mass_op_user_clear_column(): missing params')
    end

    ok = false

    begin
      user = User.find(user_id)

      if column == 'eid' && user.puavoExternalID
        user.puavoExternalID = nil
        user.save!
      elsif column == 'email' && user.mail
        user.mail = nil
        user.save!
      elsif column == 'telephone' && user.telephoneNumber
        user.telephoneNumber = nil
        user.save!
      elsif column == 'learner_id' && user.puavoExternalData
        ed = JSON.parse(user.puavoExternalData)

        if ed.include?('learner_id') && ed['learner_id']
          ed.delete('learner_id')
          user.puavoExternalData = ed.empty? ? nil : ed.to_json
          user.save!
        end
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


  # Mass operation: create a new username list from the selected users.
  # This is a "single shot" operation, it processes all selected users
  # in one call.
  def mass_op_username_list
    begin
      user_ids = params[:user][:user_ids]
    rescue
      puts "mass_op_username_list(): missing required params in the request:"
      puts params.inspect
      return status_failed_msg('mass_op_username_list(): missing params')
    end

    ok = false

    begin
      # Find the users. They must all exist.
      user_ids.each do |id|
        begin
          User.find(id)
        rescue StandardError => e
          return status_failed_msg("User ID #{id} not found: #{e}")
        end
      end

      creator = nil
      creator = params[:user][:creator] if params[:user].include?(:creator)

      # Okay, they exist. Create the list.
      new_list = List.new(user_ids, creator)
      new_list.save

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

    # get the creation and modification timestamps from LDAP operational attributes
    extra = User.find(params[:id], :attributes => ['createTimestamp', 'modifyTimestamp'])
    @user['createTimestamp'] = convert_timestamp(extra['createTimestamp'])
    @user['modifyTimestamp'] = convert_timestamp(extra['modifyTimestamp'])

    if @user.puavoRemovalRequestTime
      @user.puavoRemovalRequestTime = convert_timestamp(@user.puavoRemovalRequestTime)
    end

    # Is the user an organisation owner?
    organisation_owners = Array(LdapOrganisation.current.owner).each.select { |dn| dn != "uid=admin,o=puavo" } || []
    @user_is_owner = organisation_owners.include?(@user.dn)

    # List schools where this user is an admin in
    @admin_in_schools = []

    Array(@user.puavoAdminOfSchool || []).each do |dn|
      begin
        @admin_in_schools << School.find(dn)
      rescue StandardError => e
        logger.error "Unable to find admin school by DN \"#{dn.to_s}\": #{e}"
      end
    end

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
        by_school_hash[group.school.dn] = [group.school, []]
      end

      by_school_hash[group.school.dn][1] << group
    end

    # flatten the hash and sort the schools by name
    @user_groups = []

    by_school_hash.each { |_, data| @user_groups << data }
    @user_groups.sort! { |a, b| a[0].displayName.downcase <=> b[0].displayName.downcase }

    # then sort the per-school group lists by name
    @user_groups.each do |data|
      data[1].sort! { |a, b| a.displayName.downcase <=> b.displayName.downcase }
    end

    @viewer_is_an_owner = is_owner?

    @permit_user_deletion = false

    @own_page = current_user.id == @user.id

    if @viewer_is_an_owner
      # Owners can always delete users
      @permit_user_deletion = true
    else
      # This user is not an owner, but they *have* to be a school admin, because only owners
      # and school admins can log in. See if they've been granted any extra permissions.
      if can_schooladmin_do_this?(current_user.uid, :delete_single_users)
        @permit_user_deletion = true
      end
    end

    # Learner ID
    @learner_id = nil

    if @user.puavoExternalData
      begin
        ed = JSON.parse(@user.puavoExternalData)
        @learner_id = ed.fetch('learner_id', nil)
      rescue
      end
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
    unless is_owner?
      unless can_schooladmin_do_this?(current_user.uid, :create_single_users)
        flash[:alert] = t('flash.you_must_be_an_owner')
        redirect_to users_path
        return
      end
    end

    @user = User.new
    @groups = @school.groups

    @edu_person_affiliation = @user.puavoEduPersonAffiliation || []

    @automatic_email_addresses, @automatic_email_domain = get_automatic_email_addresses

    @is_new_user = true
    setup_integrations_for_form(@school, true)

    respond_to do |format|
      format.html # new.html.erb
      format.xml  { render :xml => @user }
    end
  end

  # GET /:school_id/users/1/edit
  def edit
    @user = get_user(params[:id])
    return if @user.nil?

    @groups = @school.groups

    @edu_person_affiliation = @user.puavoEduPersonAffiliation || []

    @automatic_email_addresses, @automatic_email_domain = get_automatic_email_addresses

    @is_new_user = false
    setup_integrations_for_form(@school, false)

    get_user_groups
  end

  # POST /:school_id/users
  # POST /:school_id/users.xml
  def create
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
        format.html { redirect_to( group_user_path(@school,@user) ) }
        format.json { render :json => nil }
      rescue UserError => e
        logger.info "Create user, Exception: " + e.to_s
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

                s.ldap_modify_operation(:delete, [{"puavoSchoolAdmin" => [@user.dn.to_s]}])
                @user.ldap_modify_operation(:delete, [{"puavoAdminOfSchool" => [s.dn.to_s]}])
              rescue StandardError => e
                raise UserError, I18n.t('flash.user.save_failed_school_admin_removal')
              end
            end
          end
        end

        up = user_params()

        # Automatically update the email address. We have to manipulate the user_params
        # array, because the actual update logic happens inside @user.update_attributes()
        # and we can't easily change it (the base method comes from the activeldap gem).
        # So instead simulate the email address field being edited.
        @automatic_email_addresses, @automatic_email_domain = get_automatic_email_addresses

        if @automatic_email_addresses
          up['mail'] = ["#{up['uid'].strip}@#{@automatic_email_domain}"]
        end

        unless @user.update_attributes(up)
          raise UserError, I18n.t('flash.user.save_failed')
        end

        if params["teaching_group"]
          @user.teaching_group = params["teaching_group"]
        end
        if params["administrative_groups"]
          @user.administrative_groups = params["administrative_groups"].delete_if{ |id| id == "0" }
          params["user"].delete("administrative_groups")
        end

        # Save new password to session otherwise next request does not work
        if session[:dn] == @user.dn
          unless params[:user][:new_password].nil? || params[:user][:new_password].empty?
            session[:password_plaintext] = params[:user][:new_password]
          end
        end
        flash[:notice] = t('flash.updated', :item => t('activeldap.models.user'))
        format.html { redirect_to( user_path(@school,@user) ) }
      rescue UserError => e
        get_user_groups
        error_message_and_render(format, 'edit',  e.message)
      end
    end
  end

  # DELETE /:school_id/users/1
  # DELETE /:school_id/users/1.xml
  def destroy
    # Can't use redirected_nonowner_user? here because we must allow school admins
    # to get here too if it has been explicitly allowed
    permit_user_deletion = false

    if is_owner?
      # Owners can always delete users
      permit_user_deletion = true
    else
      # This user is not an owner, but they *have* to be a school admin, because only owners
      # and school admins can log in. See if they've been granted any extra permissions.
      if can_schooladmin_do_this?(current_user.uid, :delete_single_users)
        permit_user_deletion = true
      end
    end

    unless permit_user_deletion
      flash[:alert] = t('flash.you_must_be_an_owner')
      redirect_to schools_path
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

      # Any primary devices? LDAP is not a relational database, so manually break the
      # connection between a deleted user and devices where they were the primary user.
      user_devices = Device.find(:all,
                                 :attribute => 'puavoDevicePrimaryUser',
                                 :value => @user.dn.to_s)

      user_devices.each do |device|
        begin
          device.puavoDevicePrimaryUser = nil
          device.save!
        rescue
          # If the primary user cannot be cleared, CANCEL the deletion
          flash[:alert] = t('flash.device_primary_user_removal_failed')
          redirect_to(user_path(@school, @user))
          return
        end
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

      schools = Array(@user.puavoSchool.dup)
      schools.reject!{ |s| s.to_s == @target.dn.to_s }
      @user.puavoSchool = (schools.count == 1) ? schools[0] : schools

      # Remove school admin associations if needed
      Array(@user.puavoAdminOfSchool).each do |dn|
        if dn.to_s == @target.dn.to_s
          @user.puavoAdminOfSchool = Array(@user.puavoAdminOfSchool).reject{ |dn| dn.to_s == @target.dn.to_s }
          @target.puavoSchoolAdmin = Array(@target.puavoSchoolAdmin).reject{ |dn| dn.to_s == @user.dn.to_s }
          @target.save!
          break
        end
      end

      @user.save!

      # The system appears to automatically add the user's UID and DN to the relevant arrays,
      # but it won't *remove* them
      LdapBase.ldap_modify_operation(@target.dn, :delete, [{ "member" => [@user.dn.to_s] }])
      LdapBase.ldap_modify_operation(@target.dn, :delete, [{ "memberUid" => [@user.uid.to_s] }])

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
      LdapBase.ldap_modify_operation(@previous.dn, :delete, [{ "member" => [@user.dn.to_s] }])
      LdapBase.ldap_modify_operation(@previous.dn, :delete, [{ "memberUid" => [@user.uid.to_s] }])

      flash[:notice] = t('flash.user.user_moved_to_school', :name => @target.displayName)
    rescue StandardError => e
      logger.error('-' * 50)
      logger.error(e)
      logger.error('-' * 50)
      flash[:alert] = t('flash.user.school_moving_failed')
    end

    redirect_to(change_schools_path(@user.primary_school, @user))
  end

  # GET /users/:school_id/users/:id/group
  def group
    @user = User.find(params[:id])

    get_user_groups

    respond_to do |format|
      format.html
    end
  end

  # PUT /users/:school_id/users/:id/group
  def add_group
    @user = User.find(params[:id])

    if params["administrative_groups"]
      @user.administrative_groups = params["administrative_groups"].delete_if{ |id| id == 0 }
    end
    @user.teaching_group = params["teaching_group"]

    respond_to do |format|
      format.html { redirect_to( user_path(@school, @user) ) }
    end
  end

  def username_redirect
    user = User.find(:first, :attribute => "uid", :value => params["username"])
    if user.nil?
      return render :plain => "Unknown user #{ ActionController::Base.helpers.sanitize(params["username"]) }", :status => 400
    end
    redirect_to user_path(params["school_id"], user.id)
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

  def get_user_groups
    @teaching_groups = rest_proxy.get("/v3/schools/#{ @school.puavoId }/teaching_groups").parse
    administrative_groups = rest_proxy.get("/v3/administrative_groups").parse or []

    @administrative_groups_by_school = {}
    administrative_groups.each do |g|
      unless @administrative_groups_by_school[g["school_id"]]
        @administrative_groups_by_school[g["school_id"]] = {}
        @administrative_groups_by_school[g["school_id"]]["school_name"] = School.find(g["school_id"]).displayName
      @administrative_groups_by_school[g["school_id"]]["groups"] = []
      end
      @administrative_groups_by_school[g["school_id"]]["groups"].push g
    end

  end

  private
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

    # Delete the user from external systems. Returns [status, message] tuples;
    # if 'status' is false, you can display 'message' to the user.
    # See app/lib/puavo/integrations.rb for details
    def delete_user_from_external_systems(user, plaintext_message: false)
      # Have actions for user deletion? Currently we only check the primary school
      # (this decision will cause trouble later on).
      organisation = LdapOrganisation.current.cn
      school = user.primary_school

      unless school_has_sync_actions_for?(organisation, school.id, :delete_user)
        return true, nil
      end

      actions = get_school_sync_actions(organisation, school.id, :delete_user)

      logger.info("School (#{school.cn}) in organisation \"#{organisation}\" " \
                  "has #{actions.length} synchronous action(s) defined for user " \
                  "deletion: #{actions.keys.join(', ')}")

      integration_names = get_school_integration_names(organisation, school.id)
      ok_systems = []

      # Process each system in sequence, bail out on the first error. 'params' are
      # the parameters defined for the action in organisations.yml.
      actions.each do |system, params|
        request_id = generate_synchronous_call_id()

        logger.info("Synchronously deleting user \"#{user.uid}\" (#{user.id}) from external " \
                    "system \"#{system}\", request ID is \"#{request_id}\"")

        status, code = do_synchronous_action(
          :delete_user, system, request_id, params,
          # -----
          organisation: organisation,
          user: user,
          school: school
        )

        if status
          ok_systems << integration_names[system]
          next
        end

        # The operation failed, format an error message
        msg = t('flash.user.synchronous_actions.deletion.part1',
                :system => integration_names[system],
                :reason => t('flash.integrations.' + code)) + '<br>'

        unless ok_systems.empty?
          msg += '<small>' +
                 t('flash.user.synchronous_actions.deletion.part2',
                   :ok_systems => ok_systems.join(', ')) +
                 '</small><br>'
        end

        msg += '<small>' +
               t('flash.user.synchronous_actions.deletion.part3',
                 :code => request_id) +
               '</small>'

        if plaintext_message
          # strip out HTML and convert newlines, to make the message "plain text"
          msg = msg.gsub!('<br>', "\n\n")
          msg = ActionView::Base.full_sanitizer.sanitize(msg)
        end

        return false, msg
      end

      logger.info('Synchronous action(s) completed without errors, proceeding with user deletion')
      return true, nil
    end
end
