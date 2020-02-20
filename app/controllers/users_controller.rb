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
      # Split the user list in two halves: one for normal users, one for users who have
      # been marked for deletion. Both arrays are displayed in their own table.
      @users, @users_marked_for_deletion = @users.partition { |u| u["puavoRemovalRequestTime"].nil? }

      now = Time.now.utc

      @users_marked_for_deletion.each do |u|
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
    respond_to do |format|
      format.html # index.html.erb
    end
  end

  def get_school_users_list
    attributes = [
      'puavoId',
      'sn',
      'givenName',
      'uid',
      'puavoEduPersonAffiliation',
      'puavoExternalId',
      'telephoneNumber',
      'displayName',
      'homeDirectory',
      'mail',
      'puavoRemovalRequestTime',
      'puavoDoNotDelete',
      'puavoLocked',
      'createTimestamp',    # LDAP operational attribute
      'modifyTimestamp'     # LDAP operational attribute
    ]

    raw = User.search_as_utf8(:filter => "(puavoSchool=#{@school.dn})",
                              :scope => :one,
                              :attributes => attributes)

    # convert the raw data into something we can easily parse in JavaScript
    users = []

    user_types = {}

    raw.each do |dn, usr|
      u = {
        id: usr['puavoId'][0].to_i,
        first: usr['givenName'] ? usr['givenName'][0] : nil,
        last: usr['sn'] ? usr['sn'][0] : nil,
        name: "#{usr['givenName'][0]} #{usr['sn'][0]}",
        uid: usr['uid'][0],
        eid: usr['puavoExternalId'] ? usr['puavoExternalId'][0] : nil,
        type: nil,
        phone: usr['telephoneNumber'] ? Array(usr['telephoneNumber']) : nil,
        email: usr['mail'] ? Array(usr['mail']) : nil,
        home: usr['homeDirectory'][0],
        dnd: usr['puavoDoNotDelete'] ? true : false,
        locked: usr['puavoLocked'] ? (usr['puavoLocked'][0] == 'TRUE' ? true : false) : false,
        rrt: convert_ldap_time(usr['puavoRemovalRequestTime']),
        created: convert_ldap_time(usr['createTimestamp']),
        modified: convert_ldap_time(usr['modifyTimestamp']),
        link: user_path(@school, usr['puavoId'][0]),
      }

      # localise user types, the table sorter will otherwise sort them incorrectly
      # the types are cached, so we don't constantly look up the YAML
      if usr['puavoEduPersonAffiliation']
        types = []

        Array(usr['puavoEduPersonAffiliation']).each do |a|
          user_types[a] = t("puavoEduPersonAffiliation_#{a}") unless user_types.include?(a)
          types << user_types[a]
        end

        u[:type] = types if types
      end

      users << u
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
      puts "mass_op_user_delete(): did not required params in the request:"
      puts params.inspect
      return status_failed_msg('mass_op_user_delete(): missing params')
    end

    ok = false

    begin
      user = User.find(user_id)

      if user.puavoDoNotDelete
        return status_failed_trans('users.mass_operations.delete.deletion_prevented')
      end

      unless user.puavoRemovalRequestTime
        return status_failed_trans('users.mass_operations.delete.not_marked_for_deletion')
      end

      if user.puavoRemovalRequestTime + 7.days > Time.now.utc
        return status_failed_trans('users.mass_operations.delete.marked_too_recently')
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
      puts "mass_op_user_lock(): did not required params in the request:"
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
      puts "mass_op_user_mark(): did not required params in the request:"
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

    # organisation owner or school admin?
    # TODO: This only checks the primary school, but users can be admins in multiple schools!
    organisation_owners = LdapOrganisation.current.owner.each.select { |dn| dn != "uid=admin,o=puavo" } || []
    school_admins = @school.user_school_admins if @school

    @is_owner = organisation_owners.include?(@user.dn)
    @is_admin = school_admins && school_admins.include?(@user)

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

    respond_to do |format|
      format.html # show.html.erb
      format.xml  { render :xml => @user }
      # FIXME, remove user key?
      format.json  { render :json => @user  }
    end
  end

  # GET /:school_id/users/new
  # GET /:school_id/users/new.xml
  def new
    @user = User.new
    @groups = @school.groups
    @roles = @school.roles
    @user_roles =  []

    @edu_person_affiliation = @user.puavoEduPersonAffiliation || []

    @is_new_user = true

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
    @roles = @school.roles
    @user_roles =  @user.roles || []

    @edu_person_affiliation = @user.puavoEduPersonAffiliation || []

    @is_new_user = false

    get_user_groups
  end

  # POST /:school_id/users
  # POST /:school_id/users.xml
  def create
    @user = User.new(user_params)
    @groups = @school.groups
    @roles = @school.roles
    @user_roles =  []

    # TODO: should we use the filtered hash returned by "user_params" here
    # instead of modifying the raw unfiltered "params" object?
    params[:user][:puavoEduPersonAffiliation] ||= []
    @edu_person_affiliation = params[:user][:puavoEduPersonAffiliation]

    @user.puavoSchool = @school.dn

    respond_to do |format|
      begin
        unless @user.save
          raise User::UserError, I18n.t('flash.user.create_failed')
        end
        if new_group_management?(@school)
          format.html { redirect_to( group_user_path(@school,@user) ) }
          format.json { render :json => nil }
        else
          flash[:notice] = t('flash.added', :item => t('activeldap.models.user'))
          format.html { redirect_to( user_path(@school,@user) ) }
          format.json { render :json => nil }
        end
      rescue User::UserError => e
        logger.info "Create user, Exception: " + e.to_s
        @user_roles = params[:user][:role_ids].nil? ? [] : Role.find(params[:user][:role_ids]) || []
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
    @roles = @school.roles
    @user_roles =  @user.roles || []

    params[:user][:puavoEduPersonAffiliation] ||= []
    @edu_person_affiliation = params[:user][:puavoEduPersonAffiliation]

    respond_to do |format|
      begin

        # Detect admin role changes
        was_admin = @user.puavoEduPersonAffiliation.include?("admin")
        is_admin = @edu_person_affiliation.include?("admin")

        if was_admin && !is_admin
          # This user used to be an admin. If they were a school admin or an organisation owner
          # we must remove them from those lists.

          # Copy-pasted from the "destroy" method below
          organisation_owners = LdapOrganisation.current.owner.each.select { |dn| dn != "uid=admin,o=puavo" }

          if organisation_owners && organisation_owners.include?(@user.dn)
            begin
              LdapOrganisation.current.remove_owner(@user)
            rescue StandardError => e
              logger.error e
              raise User::UserError, I18n.t('flash.user.save_failed_organsation_owner_removal')
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
                raise User::UserError, I18n.t('flash.user.save_failed_school_admin_removal')
              end
            end
          end
        end

        unless @user.update_attributes(user_params)
          raise User::UserError, I18n.t('flash.user.save_failed')
        end

        if new_group_management?(@school)
          if params["teaching_group"]
            @user.teaching_group = params["teaching_group"]
          end
          if params["administrative_groups"]
            @user.administrative_groups = params["administrative_groups"].delete_if{ |id| id == "0" }
            params["user"].delete("administrative_groups")
          end
        end

        # Save new password to session otherwise next request does not work
        if session[:dn] == @user.dn
          unless params[:user][:new_password].nil? || params[:user][:new_password].empty?
            session[:password_plaintext] = params[:user][:new_password]
          end
        end
        flash[:notice] = t('flash.updated', :item => t('activeldap.models.user'))
        format.html { redirect_to( user_path(@school,@user) ) }
      rescue User::UserError => e
        @user_roles = params[:user][:role_ids].nil? ? [] : Role.find(params[:user][:role_ids]) || []
        get_user_groups
        error_message_and_render(format, 'edit',  e.message)
      end
    end
  end

  # DELETE /:school_id/users/1
  # DELETE /:school_id/users/1.xml
  def destroy
    @user = get_user(params[:id])
    return if @user.nil?

    if @user.puavoDoNotDelete
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
        owners = LdapOrganisation.current.owner.each.select { |dn| dn != "uid=admin,o=puavo" }.map{ |o| o.to_s }

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

      if @user.destroy
        flash[:notice] = t('flash.destroyed', :item => t('activeldap.models.user'))
      end
    end

    respond_to do |format|
      format.html { redirect_to(users_url) }
      format.xml  { head :ok }
    end
  end

  # POST /:school_id/users/change_school
  def change_school
    @new_school = School.find(params[:new_school])

    use_groups = new_group_management?(@school)
    @role_or_group = use_groups ? Group.find(params[:new_role]) : Role.find(params[:new_role])

    params[:user_ids].each do |user_id|
      @user = User.find(user_id)
      @user.change_school(@new_school.dn.to_s)

      if use_groups
        if @user.puavoEduPersonAffiliation == 'student'
          # User.teaching_group=() wants the group ID, not the object
          @user.teaching_group = @role_or_group.id
        else
          # This method accepts arrays, but here we only permit one administrative group.
          # The user editor form lets you assign multiple administrative groups.
          @user.administrative_groups = Array(@role_or_group.id)
        end
      else
        @user.role_ids = Array(@role_or_group.id)
      end

      @user.save
    end

    respond_to do |format|
      if Array(params[:user_ids]).length > 1
        format.html { redirect_to( role_path( @new_school,
                                              @role_or_group ),
                                   :notice => t("flash.user.school_changed") ) }
      else
        format.html { redirect_to( user_path(@new_school, @user),
                                   :notice => t("flash.user.school_changed") ) }
      end
    end
  end

  # GET /:school_id/users/:id/select_school
  def select_school
    @user = User.find(params[:id])
    @schools = School.all_with_permissions current_user

    # don't show the school the user already is in
    user_school_id = @user.puavoSchool&.rdns[0]["puavoId"] || -1
    @schools.reject! { |s| s.id == user_school_id }

    respond_to do |format|
      format.html
    end
  end

  # POST /:school_id/users/:id/select_role
  def select_role
    @user = User.find(params[:id])
    @new_school = School.find(params[:new_school])

    @use_groups = new_group_management?(@school)
    @roles_or_groups = @use_groups ? @new_school.groups : @new_school.roles
    @is_a_student = false

    if @use_groups
      # only show certain kinds of groups, based on the user's type
      if @user.puavoEduPersonAffiliation == 'student'
        # display only teaching groups for students
        @roles_or_groups.select! { |g| g.puavoEduGroupType == 'teaching group' }
        is_a_student = true
      else
        # for everyone else, teachers or not, display only administrative groups
        @roles_or_groups.select! { |g| g.puavoEduGroupType == 'administrative group' }
      end
    end

    if @roles_or_groups.nil? || @roles_or_groups.empty?
      if is_a_student
        # special message for students
        flash[:alert] = t('users.select_school.no_teaching_groups')
      else
        if @use_groups
          flash[:alert] = t('users.select_school.no_admin_groups')
        else
          flash[:alert] = t('users.select_school.no_roles')
        end
      end

      redirect_back fallback_location: users_path(@school)
    else
      respond_to do |format|
        format.html
      end
    end
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

    if @user.puavoDoNotDelete
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
    @user = User.find(params[:id])

    @user.puavoDoNotDelete = true
    @user.puavoRemovalRequestTime = nil
    @user.save

    flash[:notice] = t('flash.user.deletion_prevented')

    respond_to do |format|
      format.html { redirect_to( user_path(@school, @user) ) }
    end
  end

  def lock_marked_users
    # find all users who are marked for deletion
    lock_these = @school.members.reject{ |m| m.puavoRemovalRequestTime.nil? }

    # then ignore those who are already locked
    lock_these.reject!{ |m| m.puavoLocked && m.puavoLocked == true }

    # lock them
    if lock_these.nil? || lock_these.empty?
      flash[:notice] = t('flash.user.marked_users_locked_none')
    else
      succeed = 0
      failed = 0

      lock_these.each do |m|
        unless m.puavoDoNotDelete.nil?
          failed += 1
          next
        end

        begin
          m.puavoLocked = true
          m.save!
          succeed += 1
        rescue StandardError => e
          logger.error("lock_marked_users(): #{e}")
          failed += 1
        end
      end

      if failed == 0
        flash[:notice] = t('flash.user.marked_users_locked', :succeed => succeed)
      else
        flash[:notice] = t('flash.user.marked_users_locked_with_fail', :succeed => succeed, :failed => failed)
      end
    end

    respond_to do |format|
      format.html { redirect_to( users_path(@school) ) }
    end
  end

  def delete_marked_users
    delete_these = @school.members.reject{|m| m.puavoRemovalRequestTime.nil? }

    succeed = 0
    failed = 0

    delete_these.each do |m|
      unless m.puavoDoNotDelete.nil?
        failed += 1
        next
      end

      begin
        m.destroy
        succeed += 1
      rescue StandardError => e
        failed += 1
      end
    end

    if failed == 0
      flash[:notice] = t('flash.user.marked_users_deleted', :succeed => succeed)
    else
      flash[:notice] = t('flash.user.marked_users_deleted_with_fail', :succeed => succeed, :failed => failed)
    end

    respond_to do |format|
      format.html { redirect_to( users_path(@school) ) }
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
          :puavoEduPersonAffiliation=>[],
          :role_ids=>[]).to_hash

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
      # Have actions for user deletion?
      school = user.school

      unless school_has_sync_actions_for?(school.id, :delete_user)
        return true, nil
      end

      actions = get_school_sync_actions(school.id, :delete_user)

      logger.info("School (#{school.cn}) has #{actions.length} synchronous " \
                  "action(s) defined for user deletion: #{actions.keys.join(', ')}")

      integration_names = get_school_integration_names(school.id)
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
          organisation: LdapOrganisation.current.cn,
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
