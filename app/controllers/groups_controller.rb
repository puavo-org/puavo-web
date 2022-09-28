require 'list'
require 'csv'

class GroupsController < ApplicationController
  include Puavo::MassOperations
  include Puavo::Helpers

  # GET /:school_id/groups/:id/members
  def members
    @group = Group.find(params[:id])

    @members, @num_hidden = get_and_sort_group_members(@group)

    respond_to do |format|
      format.json  { render :json => @members }
    end
  end

  # GET /:school_id/groups
  # GET /:school_id/groups.xml
  def index
    if test_environment? || ['application/json', 'application/xml'].include?(request.format)
      old_legacy_groups_index
    else
      new_cool_groups_index
    end
  end

  # Old "legacy" index used during tests
  def old_legacy_groups_index
    if @school
      @groups = @school.groups
    else
      @groups = Group.all
    end

    @groups.sort! do |a, b|
      a["displayName"].downcase <=> b["displayName"].downcase
    end

    if params[:memberUid]
      @groups.delete_if{ |g| !Array(g.memberUid).include?(params[:memberUid]) }
    end

    respond_to do |format|
      format.html # index.html.erb
      format.xml  { render :xml => @groups }
      format.json { render :json => @groups }
    end
  end

  # New AJAX-based index for non-test environments
  def new_cool_groups_index
    @is_owner = is_owner?

    respond_to do |format|
      format.html # index.html.erb
    end
  end

  # AJAX call
  def get_school_groups_list
    # Get a raw list of groups in this school
    raw = Group.search_as_utf8(:filter => "(puavoSchool=#{@school.dn})",
                               :scope => :one,
                               :attributes => GroupsHelper.get_group_attributes())

    # Convert the raw data into something we can easily parse in JavaScript
    school_id = @school.id.to_i
    groups = []

    raw.each do |dn, grp|
      # Common attributes
      group = GroupsHelper.convert_raw_group(dn, grp)

      # Special attributes
      group[:link] = "/users/#{@school.id}/groups/#{group[:id]}"
      group[:school_id] = school_id

      groups << group
    end

    render :json => groups
  end

  # ------------------------------------------------------------------------------------------------
  # ------------------------------------------------------------------------------------------------

  # Mass operation: delete group
  def mass_op_group_delete
    begin
      group_id = params[:group][:id]
    rescue
      puts "mass_op_group_delete(): missing required params in the request:"
      puts params.inspect
      return status_failed_msg('mass_op_group_delete(): missing params')
    end

    ok = false

    begin
      group = Group.find(group_id)
      group.destroy
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

  # Mass operation: clear group (remove all users from it)
  def mass_op_group_clear
    begin
      group_id = params[:group][:id]
    rescue
      puts "mass_op_group_clear(): missing required params in the request:"
      puts params.inspect
      return status_failed_msg('mass_op_group_clear(): missing params')
    end

    ok = false

    begin
      group = Group.find(group_id)
      ok = _remove_all_group_members(group)
    rescue StandardError => e
      return status_failed_msg(e)
    end

    if ok
      return status_ok()
    else
      return status_failed_msg('unknown_error')
    end
  end

  # Mass operation: lock or unlock all group members
  def mass_op_group_lock_members
    begin
      group_id = params[:group][:id]
      state = params[:group][:state]
    rescue
      puts "mass_op_group_lock_members(): missing required params in the request:"
      puts params.inspect
      return status_failed_msg('mass_op_group_lock_members(): missing params')
    end

    ok = false

    begin
      group = Group.find(group_id)
      _lock_members(group, state)
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

  # Mass operation: mark (or unmark) all group members for deletion
  def mass_op_group_mark_members_for_deletion
    begin
      group_id = params[:group][:id]
      state = params[:group][:state]
    rescue
      puts "mass_op_group_mark_members_for_deletion(): missing required params in the request:"
      puts params.inspect
      return status_failed_msg('mass_op_group_mark_members_for_deletion(): missing params')
    end

    ok = false

    begin
      group = Group.find(group_id)
      _mark_members_for_deletion(group, state)
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

  # Mass operation: modify memberships (see below)
  def mass_op_change_members
    begin
      user_id = params[:group][:id]
      mode = params[:group][:mode]
      groups = params[:group][:groups]
    rescue
      puts "mass_op_change_members(): missing required params in the request:"
      puts params.inspect
      return status_failed_msg('mass_op_change_members(): missing params')
    end

    ok = false

    begin
      u = User.find(user_id)

      groups.each do |id|
        g = Group.find(id)

        # add_user and remove_user handle duplicates and non-existent members gracefully
        if mode == 'add'
          g.add_user(u)
        else
          g.remove_user(u)
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

  # ------------------------------------------------------------------------------------------------
  # ------------------------------------------------------------------------------------------------

  # GET /:school_id/groups/1
  # GET /:school_id/groups/1.xml
  def show
    @group = get_group(params[:id])
    return if @group.nil?

    # get the creation and modification timestamps from LDAP operational attributes
    extra = Group.find(params[:id], :attributes => ['createTimestamp', 'modifyTimestamp'])
    @group['createTimestamp'] = convert_timestamp(extra['createTimestamp'])
    @group['modifyTimestamp'] = convert_timestamp(extra['modifyTimestamp'])

    @members, @num_hidden = get_and_sort_group_members(@group)

    respond_to do |format|
      format.html # show.html.erb
      format.xml  { render :xml => @group }
    end
  end

  # GET /:school_id/groups/new
  # GET /:school_id/groups/new.xml
  def new
    @group = Group.new
    @is_new_group = true

    respond_to do |format|
      format.html # new.html.erb
      format.xml  { render :xml => @group }
    end
  end

  # GET /:school_id/groups/1/edit
  def edit
    @group = get_group(params[:id])
    @is_new_group = false
    return if @group.nil?
  end

  # POST /:school_id/groups
  # POST /:school_id/groups.xml
  def create
    @group = Group.new(group_params)

    @group.puavoSchool = @school.dn

    respond_to do |format|
      if @group.save
        flash[:notice] = t('flash.added', :item => t('activeldap.models.group'))
        format.html { redirect_to( group_path(@school, @group) ) }
        format.xml  { render :xml => @group, :status => :created, :location => @group }
      else
        flash[:alert] = t('flash.create_failed', :model => t('activeldap.models.group').downcase )
        format.html { render :action => "new" }
        format.xml  { render :xml => @group.errors, :status => :unprocessable_entity }
      end
    end
  end

  # PUT /:school_id/groups/1
  # PUT /:school_id/groups/1.xml
  def update
    @group = get_group(params[:id])
    return if @group.nil?

    respond_to do |format|
      if @group.update_attributes(group_params)
        flash[:notice] = t('flash.updated', :item => t('activeldap.models.group'))
        format.html { redirect_to( group_path(@school, @group) ) }
        format.xml  { head :ok }
      else
        flash[:alert] = t('flash.save_failed', :model => t('activeldap.models.group') )
        format.html { render :action => "edit" }
        format.xml  { render :xml => @group.errors, :status => :unprocessable_entity }
      end
    end
  end

  # DELETE /:school_id/groups/1
  # DELETE /:school_id/groups/1.xml
  def destroy
    @group = get_group(params[:id])
    return if @group.nil?

    respond_to do |format|
      if @group.destroy
        flash[:notice] = t('flash.destroyed', :item => t('activeldap.models.group'))
        format.html { redirect_to(groups_url) }
        format.xml  { head :ok }
      else
        format.html { redirect_to(groups_url) }
        format.xml  { render :xml => @group.errors, :status => :unprocessable_entity }
      end
    end
  end

  # PUT /:school_id/groups/:group_id/create_username_list_from_group
  def create_username_list_from_group
    @group = get_group(params[:id])
    return if @group.nil?

    if @group.members.empty?
      flash[:notice] = t('flash.group.empty_group')
      redirect_to group_path(@school, @group)
      return
    end

    begin
      if is_owner?
        new_list = List.new(@group.members.map { |u| u.id }, current_user.uid)
      else
        only_these = Set.new(Array(current_user.puavoAdminOfSchool || []).map { |dn| dn.to_s })
        members = []

        @group.members.collect do |member|
          # Try to access the primary school of this group member. If it throws an exception,
          # then the member is in a school the current user (the user viewing this page)
          # cannot access. A bit hacky...
          begin
            member.primary_school.cn
          rescue
            next
          end

          members << member
        end

        new_list = List.new(members.map { |u| u.id }, current_user.uid)
      end

      new_list.save
      ok = true
    rescue
      ok = false
    end

    respond_to do |format|
      if ok
        flash[:notice] = t('flash.group.create_username_list_ok', :name => @group.displayName)
        format.html { redirect_to lists_path(@school) }
      else
        flash[:alert] = t('flash.group.create_username_list_failed')
        format.html { redirect_to group_path(@school, @group) }
      end
    end
  end

  # PUT /:school_id/groups/:group_id/mark_group_members_for_deletion
  def mark_group_members_for_deletion
    @group = get_group(params[:id])
    return if @group.nil?

    if @group.members.empty?
      flash[:notice] = t('flash.group.empty_group')
      redirect_to group_path(@school, @group)
      return
    end

    count = _mark_members_for_deletion(@group, true)

    respond_to do |format|
      flash[:notice] = t('flash.group.members_marked', :count => count)
      format.html { redirect_to group_path(@school, @group) }
    end
  end

  # PUT /:school_id/groups/:group_id/unmark_group_members_deletion
  def unmark_group_members_deletion
    @group = get_group(params[:id])
    return if @group.nil?

    if @group.members.empty?
      flash[:notice] = t('flash.group.empty_group')
      redirect_to group_path(@school, @group)
      return
    end

    count = _mark_members_for_deletion(@group, false)

    respond_to do |format|
      flash[:notice] = t('flash.group.members_unmarked', :count => count)
      format.html { redirect_to group_path(@school, @group) }
    end
  end

  # PUT /:school_id/groups/:group_id/lock_all_members
  def lock_all_members
    @group = get_group(params[:id])
    return if @group.nil?

    if @group.members.empty?
      flash[:notice] = t('flash.group.empty_group')
      redirect_to group_path(@school, @group)
      return
    end

    count = _lock_members(@group, true)

    respond_to do |format|
      flash[:notice] = t('flash.group.members_locked', :count => count)
      format.html { redirect_to group_path(@school, @group) }
    end
  end

  # PUT /:school_id/groups/:group_id/unlock_all_members
  def unlock_all_members
    @group = get_group(params[:id])
    return if @group.nil?

    if @group.members.empty?
      flash[:notice] = t('flash.group.empty_group')
      redirect_to group_path(@school, @group)
      return
    end

    count = _lock_members(@group, false)

    respond_to do |format|
      flash[:notice] = t('flash.group.members_unlocked', :count => count)
      format.html { redirect_to group_path(@school, @group) }
    end
  end

  # GET /:school_id/groups/:group_id/select_new_school
  def select_new_school
    @group = get_group(params[:id])
    return if @group.nil?

    @available_schools = School.all.select { |s| s.id != @group.school.id }

    unless is_owner?
      # School admins can only transfer groups between the schools they're admins in
      # TODO: This is starting to be a recurring pattern. See if this could be moved to
      # its own utility function.
      only_these = Set.new(Array(current_user.puavoAdminOfSchool || []).map { |dn| dn.to_s })
      @available_schools.delete_if { |s| !only_these.include?(s.dn.to_s) }
    end

    if @available_schools.empty?
      flash[:notice] = t('flash.group.no_other_available_schools')
      return redirect_to group_path(@school, @group)
    end

    respond_to do |format|
      format.html
    end
  end

  # PUT /:school_id/groups/:group_id/change_school
  def change_school
    @group = get_group(params[:id])
    return if @group.nil?

    begin
      school = School.find(params[:school])
    rescue ActiveLdap::EntryNotFound => e
      flash[:alert] = t('flash.invalid_school_id')
      return redirect_to group_path(@school, @group)
    end

    unless is_owner?
      only_these = Set.new(Array(current_user.puavoAdminOfSchool || []).map { |dn| dn.to_s })

      unless only_these.include?(school.dn.to_s)
        flash[:alert] = t('flash.invalid_school_id')
        return redirect_to group_path(@school, @group)
      end
    end

    begin
      @group.puavoSchool = school.dn
      @group.save!
    rescue => e
      flash[:alert] = t('flash.save_failed')    # Not the best possible error message
      return redirect_to group_path(@school, @group)
    end

    flash[:notice] = t('flash.group.school_changed', new_school: school.displayName)

    # Don't use @school or @group.school here, they still point to the previous school
    return redirect_to group_path(school, @group)
  end

  def remove_user
    @group = Group.find(params[:id])
    @user = User.find(params[:user_id])

    @group.remove_user(@user)

    # @group.reload does not seem to work correctly when removing
    # the last member of a group?
    @group = Group.find(params[:id])

    @members, @num_hidden = get_and_sort_group_members(@group)

    respond_to do |format|
      format.html { render :plain => "OK" }
      format.js
    end
  end

  # GET /:school_id/groups/mass_members_edit
  def members_mass_edit
    return if redirected_nonowner_user?

    @initial_groups = get_plain_groups_list(@school.dn)

    respond_to do |format|
      format.html { render action: 'members_mass_edit' }
    end
  end

  # Retrieve groups for the target groups list (this isn't dynamic, the groups list is updated
  # ONLY when the page is loaded)
  def get_plain_groups_list(school_dn)
    Group.search_as_utf8(
      filter: "(&(objectClass=puavoEduGroup)(puavoSchool=#{Net::LDAP::Filter.escape(school_dn.to_s)}))",
      attributes: ['puavoId', 'cn', 'displayName', 'puavoSchool', 'puavoEduGroupType', 'member']
    ).collect do |dn, raw|
      {
        id: raw['puavoId'][0].to_i,
        name: raw['displayName'][0],
        sortName: raw['displayName'][0].downcase,
        abbr: raw['cn'][0],
        type: raw.fetch('puavoEduGroupType', [nil])[0],
      }
    end.sort do |a, b|
      a[:sortName] <=> b[:sortName]
    end.each do |g|
      # The "sortName" is used to avoid repeated downcase calls during sorting
      g.delete(:sortName)
    end
  end

  # AJAX call
  def update_groups_list
    render json: get_plain_groups_list(@school.dn)
  end

  # AJAX call
  def get_all_groups_members
    dn_to_uid = /\d+/

    schools = {}
    groups = {}
    users = {}

    # Grab schools (groups can be in other schools than the current)
    School.search_as_utf8(
      attributes: ['puavoId', 'displayName']
    ).map do |dn, raw|
      schools[dn] = {
        id: raw['puavoId'][0].to_i,
        name: raw['displayName'][0],
      }
    end

    # Get users
    User.search_as_utf8(
      filter: "(&(objectClass=puavoEduPerson)(puavoSchool=#{@school.dn.to_s}))",
      attributes: ['puavoId', 'givenName', 'sn', 'uid', 'puavoEduPersonAffiliation',
                   'puavoLocked', 'puavoRemovalRequestTime']
    ).map do |dn, raw|
      uid = raw['puavoId'][0].to_i

      users[uid] = {
        id: uid,
        first: raw['givenName'][0],
        last: raw['sn'][0],
        uid: raw['uid'][0],
        role: Array(raw['puavoEduPersonAffiliation'] || []),
        locked: raw.include?('puavoLocked') && raw['puavoLocked'][0] == 'TRUE',
        groups: [],
      }

      if raw.include?('puavoRemovalRequestTime') && raw['puavoRemovalRequestTime']
        users[uid][:marked] = Puavo::Helpers::convert_ldap_time(raw['puavoRemovalRequestTime'])
      end
    end

    # Get groups and their members
    Group.search_as_utf8(
      filter: "(objectClass=puavoEduGroup)",
      attributes: ['puavoId', 'cn', 'displayName', 'puavoSchool', 'puavoEduGroupType', 'member']
    ).each do |dn, raw|
      gid = raw['puavoId'][0].to_i

      groups[gid] = {
        name: raw['displayName'][0],
        abbr: raw['cn'][0],
        type: raw.fetch('puavoEduGroupType', [nil])[0],
        school: raw['puavoSchool'][0],
      }

      # Fill in the "groups" member for each user
      Array(raw['member'] || []).each do |dn|
        begin
          # extract the PuavoID from the DN
          uid = dn_to_uid.match(dn)[0].to_i
        rescue
          next
        end

        users[uid][:groups] << gid if users.include?(uid)
      end
    end

    # Wrap it all in one compact structure, that we'll "unpack" with JavaScript
    data = {
      schools: schools,
      groups: groups,
      users: users,
    }

    render json: data
  end

  def find_groupless_users
    # Find all users who have no groups and sort them alphabetically by name
    @users = []

    @school.members.each do |m|
      @users << m if m.groups.empty?
    end

    @users.sort! { |a, b| a.displayName.downcase <=> b.displayName.downcase }

    # List potential groups where these users could be added to
    @move_groups = []

    @school.groups.each do |g|
      @move_groups << [g.displayName, g.cn, g.id.to_i, g.puavoEduGroupType.nil? ? "(?)" : I18n.t("group_type.#{g.puavoEduGroupType}"), g.members.count]
    end

    @move_groups.sort! { |a, b| a[0].downcase <=> b[0].downcase }

    # A set of organisation owners' DNs
    @owners = Array(LdapOrganisation.current.owner)
               .reject { |dn| dn == 'uid=admin,o=puavo' }
               .collect { |o| o.to_s }.to_set

    respond_to do |format|
      format.html { render :action => 'groupless_users' }
    end
  end

  #
  def process_groupless_users
    if !params.include?(:operation) || !['lock', 'mark', 'move'].include?(params[:operation])
      flash[:alert] = t('groups.groupless_users.missing_params')
      redirect_to find_groupless_users_path(@school)
      return
    end

    # A set of organisation owners' DNs
    owners = Array(LdapOrganisation.current.owner)
              .reject { |dn| dn == 'uid=admin,o=puavo' }
              .collect { |o| o.to_s }.to_set

    now = Time.now.utc
    count = 0

    case params[:operation]
      when 'lock'
        @school.members.each do |m|
          next unless m.groups.empty?
          next if owners.include?(m.dn.to_s)
          next if m.puavoLocked

          begin
            m.puavoLocked = true
            m.save
            count += 1
          rescue => e
          end
        end

      when 'mark'
        @school.members.each do |m|
          next unless m.groups.empty?
          next if owners.include?(m.dn.to_s)
          next if m.puavoRemovalRequestTime

          begin
            m.puavoRemovalRequestTime = now
            m.puavoLocked = true
            m.save!
            count += 1
          rescue => e
          end
        end

      when 'move'
        if !params.include?(:group)
          flash[:alert] = t('groups.groupless_users.missing_params')
          redirect_to find_groupless_users_path(@school)
          return
        end

        # Can't use get_group, because it redirects to wrong page!
        begin
          group = Group.find(params[:group])
        rescue ActiveLdap::EntryNotFound => e
          flash[:alert] = t('flash.invalid_group_id', :id => params[:group])
          redirect_to find_groupless_users_path(@school)
          return
        end

        @school.members.each do |m|
          next unless m.groups.empty?
          next if owners.include?(m.dn.to_s)

          begin
            group.add_user(m)
            count += 1
          rescue => e
            logger.error(e)
          end
        end
    end

    respond_to do |format|
      flash[:notice] = t('groups.groupless_users.done', :count => count)
      format.html { redirect_to find_groupless_users_path(@school) }
    end
  end

  # Remove all members from a group
  def remove_all_members
    @group = get_group(params[:id])
    return if @group.nil?

    ok = _remove_all_group_members(@group)

    respond_to do |format|
      flash[:notice] = ok ? t('flash.group.group_emptied_ok') : t('flash.group.group_emptied_failed')
      format.html { redirect_to group_path(@school, @group) }
    end
  end

  # GET /:school_id/groups/:group_id/get_members_as_csv
  def get_members_as_csv
    @group = get_group(params[:id])
    return if @group.nil?

    output = CSV.generate(headers: true) do |csv|
      csv << ['puavoid', 'first_name', 'last_name', 'uid', 'locked', 'marked_for_deletion', 'primary_school_name', 'primary_school_abbr', 'primary_school_puavoid']

      @group.members.each do |m|
        begin
          row = []
          row << m.id
          row << m.givenName
          row << m.surname
          row << m.uid
          row << m.puavoLocked
          row << m.puavoRemovalRequestTime
          row << m.primary_school.displayName
          row << m.primary_school.cn
          row << m.primary_school.id
        rescue
          # Probably an inaccessible user, in another school the current admin has no access to?
          next
        end

        csv << row
      end
    end

    filename = "#{current_organisation.organisation_key}_#{@group.cn}_members_#{Time.now.strftime("%Y%m%d_%H%M%S")}.csv"

    send_data(output,
              filename: filename,
              type: 'text/csv',
              disposition: 'attachment' )
  end

  def add_user
    @group = Group.find(params[:id])
    @user = User.find(params[:user_id])

    @group.add_user(@user)

    @group.reload

    @members, @num_hidden = get_and_sort_group_members(@group)

    respond_to do |format|
      format.html { render :plain => "OK" }
      format.js
    end
  end

  def user_search
    @group = Group.find(params[:id])

    @users = User.words_search_and_sort_by_name(
      ["sn", "givenName", "uid"],
      lambda{ |v| "#{v['sn'].first} #{v['givenName'].first}" },
      lambda { |w| "(|(givenName=*#{w}*)(sn=*#{w}*)(uid=*#{w}*))" },
      params[:words] )

    @users.sort!{|a, b| a["name"].downcase <=> b["name"].downcase }

    @schools = Hash.new
    School.search_as_utf8( :scope => :one,
                   :attributes => ["puavoId", "displayName"] ).map do |dn, v|
      @schools[v["puavoId"].first] = v["displayName"].first
    end

    respond_to do |format|
      if @users.length == 0
        format.html { render :inline => "<p>#{t('search.no_matches')}</p>" }
      else
        format.html { render :user_search, :layout => false }
      end
    end

  end

  private
    def group_params
      # arrays must be listed last due to some weird syntax thing
      return params.require(:group).permit(:displayName, :cn, :puavoExternalId, :puavoEduGroupType).to_hash
    end

    def get_group(id)
      begin
        return Group.find(id)
      rescue ActiveLdap::EntryNotFound => e
        flash[:alert] = t('flash.invalid_group_id', :id => id)
        redirect_to groups_path(@school)
        return nil
      end
    end

    def get_and_sort_group_members(group)
      members = group.members
      num_hidden = 0

      # Hide members whose school information we cannot access. This can only (maybe?) happen
      # if you aren't an owner and you're trying to view a group which contains members from
      # other schools than yours.
      members.reject! do |m|
        begin
          # This is weird. If I check m.school.nil? it returns false, but accessing m.school
          # immediately afterwards will still fail?
          m.primary_school.cn
          false
        rescue
          num_hidden += 1
          true
        end
      end

      members.sort!{ |a, b| (a["givenName"] + a["sn"]).downcase <=> (b["givenName"] + b["sn"]).downcase }

      return members, num_hidden
    end

    # Remove all users from a group (don't delete them, just remove them from the group)
    def _remove_all_group_members(group)
      members = group.members
      ok = true

      members.each do |m|
        begin
          group.remove_user(m)
        rescue StandardError => e
          puts "===> Could not remove member #{m.uid} from group #{group.cn}: #{e}"
          ok = false
        end
      end

      ok
    end

    # Mark (or unmark) group members for deletion. Returns the number of users updated.
    def _mark_members_for_deletion(group, mark)
      now = Time.now.utc
      count = 0

      group.members.each do |u|
        begin
          if mark
            # Mark for deletion
            if u.puavoRemovalRequestTime.nil?
              u.puavoRemovalRequestTime = now
              u.puavoLocked = true
              u.save
              count += 1
            end
          else
            # Remove deletion mark
            if u.puavoRemovalRequestTime
              u.puavoRemovalRequestTime = nil
              u.save
              count += 1
            end
          end
        rescue StandardError => e
          puts "====> Could not mark/unmark group member #{u.uid} from group #{group.cn}: #{e}"
        end
      end

      return count
    end

    # Lock or unlock members
    def _lock_members(group, lock)
      count = 0

      group.members.each do |u|
        begin
          if lock
            # Lock
            unless u.puavoLocked
              u.puavoLocked = true
              u.save
              count += 1
            end
          else
            # Unlock
            if u.puavoLocked
              u.puavoLocked = nil
              u.save
              count += 1
            end
          end
        rescue StandardError => e
          puts "====> Could not lock/unlock group member #{u.uid} in group #{group.cn}: #{e}"
        end
      end

      return count
    end
end
