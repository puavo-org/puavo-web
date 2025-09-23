require 'csv'
require 'list'
require 'set'

class GroupsController < ApplicationController
  include Puavo::Helpers
  include Puavo::GroupsShared

  # GET /:school_id/groups/:id/members
  def members
    @group = Group.find(params[:id])

    @members, @num_hidden = get_and_sort_group_members(@group)

    respond_to do |format|
      format.json  { render json: @members }
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
      a['displayName'].downcase <=> b['displayName'].downcase
    end

    if params[:memberUid]
      @groups.delete_if { |g| !Array(g.memberUid).include?(params[:memberUid]) }
    end

    @is_owner = is_owner?
    @permit_group_creation = @is_owner || current_user.has_admin_permission?(:create_groups)
    @permit_group_deletion = @is_owner || current_user.has_admin_permission?(:delete_groups)

    respond_to do |format|
      format.html # index.html.erb
      format.xml  { render xml: @groups }
      format.json { render json: @groups }
    end
  end

  # New AJAX-based index for non-test environments
  def new_cool_groups_index
    @is_owner = is_owner?
    @permit_group_creation = @is_owner || current_user.has_admin_permission?(:create_groups)
    @permit_group_deletion = @is_owner || current_user.has_admin_permission?(:delete_groups)
    @permit_mass_group_deletion = @is_owner || (@permit_group_deletion && current_user.has_admin_permission?(:mass_delete_groups))
    @permit_mass_group_change_type = @is_owner || current_user.has_admin_permission?(:group_mass_change_type)

    respond_to do |format|
      format.html # index.html.erb
    end
  end

  # AJAX call
  def get_school_groups_list
    # Get a raw list of groups in this school
    raw = Group.search_as_utf8(filter: "(puavoSchool=#{@school.dn})",
                               scope: :one,
                               attributes: GroupsHelper.get_group_attributes())

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

    render json: groups
  end

  # GET /:school_id/groups/1
  # GET /:school_id/groups/1.xml
  def show
    @group = get_group(params[:id])
    return if @group.nil?

    # Get extra timestamps from LDAP operational attributes
    timestamps = Group.search_as_utf8(
      filter: "(puavoId=#{@group.id})",
      attributes: %w[createTimestamp modifyTimestamp]
    )[0][1]

    @created = Puavo::Helpers.ldap_time_string_to_utc_time(timestamps['createTimestamp'])
    @modified = Puavo::Helpers.ldap_time_string_to_utc_time(timestamps['modifyTimestamp'])

    @members, @num_hidden = get_and_sort_group_members(@group)

    @is_owner = is_owner?
    @permit_group_creation = @is_owner || current_user.has_admin_permission?(:create_groups)
    @permit_group_deletion = @is_owner || current_user.has_admin_permission?(:delete_groups)
    @permit_school_change = @is_owner || current_user.has_admin_permission?(:group_change_school)

    respond_to do |format|
      format.html # show.html.erb
      format.xml  { render xml: @group }
    end
  end

  # GET /:school_id/groups/new
  # GET /:school_id/groups/new.xml
  def new
    unless is_owner? || current_user.has_admin_permission?(:create_groups)
      flash[:alert] = t('flash.you_must_be_an_owner')
      redirect_to groups_path
      return
    end

    @group = Group.new
    @is_new_group = true

    respond_to do |format|
      format.html # new.html.erb
      format.xml  { render xml: @group }
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
    unless is_owner? || current_user.has_admin_permission?(:create_groups)
      flash[:alert] = t('flash.you_must_be_an_owner')
      redirect_to groups_path
      return
    end

    @group = Group.new(group_params)

    @group.puavoSchool = @school.dn

    respond_to do |format|
      if @group.save
        flash[:notice] = t('flash.added', item: t('activeldap.models.group'))
        format.html { redirect_to(group_path(@school, @group)) }
        format.xml  { render xml: @group, status: :created, location: @group }
      else
        flash[:alert] = t('flash.create_failed', model: t('activeldap.models.group').downcase)
        format.html { render action: 'new' }
        format.xml  { render xml: @group.errors, status: :unprocessable_entity }
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
        flash[:notice] = t('flash.updated', item: t('activeldap.models.group'))
        format.html { redirect_to(group_path(@school, @group)) }
        format.xml  { head :ok }
      else
        flash[:alert] = t('flash.save_failed', model: t('activeldap.models.group'))
        format.html { render action: 'edit' }
        format.xml  { render xml: @group.errors, status: :unprocessable_entity }
      end
    end
  end

  # DELETE /:school_id/groups/1
  # DELETE /:school_id/groups/1.xml
  def destroy
    unless is_owner? || current_user.has_admin_permission?(:delete_groups)
      flash[:alert] = t('flash.you_must_be_an_owner')
      redirect_to groups_path
      return
    end

    @group = get_group(params[:id])
    return if @group.nil?

    respond_to do |format|
      if @group.destroy
        flash[:notice] = t('flash.destroyed', item: t('activeldap.models.group'))
        format.html { redirect_to(groups_url) }
        format.xml  { head :ok }
      else
        format.html { redirect_to(groups_url) }
        format.xml  { render xml: @group.errors, status: :unprocessable_entity }
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

    full_name = "#{current_user.givenName} #{current_user.sn} (#{current_user.uid})"

    begin
      if is_owner?
        new_list = List.new(@group.members.map { |u| u.id.to_i }, full_name)
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

        new_list = List.new(members.map { |u| u.id.to_i }, full_name)
      end

      new_list.save
      ok = true
    rescue
      ok = false
    end

    respond_to do |format|
      if ok
        flash[:notice] = t('flash.group.create_username_list_ok', name: @group.displayName)
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

    count = Puavo::GroupsShared::mark_members_for_deletion(@group, true)

    respond_to do |format|
      flash[:notice] = t('flash.group.members_marked', count: count)
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

    count = Puavo::GroupsShared::mark_members_for_deletion(@group, false)

    respond_to do |format|
      flash[:notice] = t('flash.group.members_unmarked', count: count)
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

    count = Puavo::GroupsShared::lock_members(@group, true)

    respond_to do |format|
      flash[:notice] = t('flash.group.members_locked', count: count)
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

    count = Puavo::GroupsShared::lock_members(@group, false)

    respond_to do |format|
      flash[:notice] = t('flash.group.members_unlocked', count: count)
      format.html { redirect_to group_path(@school, @group) }
    end
  end

  # GET /:school_id/groups/:group_id/select_new_school
  def select_new_school
    @group = get_group(params[:id])
    return if @group.nil?

    @available_schools = School.all.select { |s| s.id != @group.school.id }

    unless is_owner?
      unless current_user.has_admin_permission?(:group_change_school)
        flash[:alert] = t('flash.you_must_be_an_owner')
        redirect_to group_path(@school, @group)
        return
      end

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

    unless is_owner? ||  current_user.has_admin_permission?(:group_change_school)
      flash[:alert] = t('flash.you_must_be_an_owner')
      redirect_to group_path(@school, @group)
      return
    end

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
      format.html { render plain: 'OK' }
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
        users[uid][:marked] = Puavo::Helpers.ldap_time_string_to_unixtime(raw['puavoRemovalRequestTime'])
      end
    end

    # Get groups and their members
    Group.search_as_utf8(
      filter: '(objectClass=puavoEduGroup)',
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
      @move_groups << [g.displayName, g.cn, g.id.to_i, g.puavoEduGroupType.nil? ? '(?)' : I18n.t("group_type.#{g.puavoEduGroupType}"), g.members.count]
    end

    @move_groups.sort! { |a, b| a[0].downcase <=> b[0].downcase }

    @owners = owners_set()

    respond_to do |format|
      format.html { render action: 'groupless_users' }
    end
  end

  #
  def process_groupless_users
    if !params.include?(:operation) || !['lock', 'mark', 'move'].include?(params[:operation])
      flash[:alert] = t('groups.groupless_users.missing_params')
      redirect_to find_groupless_users_path(@school)
      return
    end

    owners = owners_set()
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
          flash[:alert] = t('flash.invalid_group_id', id: params[:group])
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
      flash[:notice] = t('groups.groupless_users.done', count: count)
      format.html { redirect_to find_groupless_users_path(@school) }
    end
  end

  # Remove all members from a group
  def remove_all_members
    @group = get_group(params[:id])
    return if @group.nil?

    ok = Puavo::GroupsShared::remove_all_members(@group)

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
      format.html { render plain: 'OK' }
      format.js
    end
  end

  def user_search
    @group = Group.find(params[:id])

    words = Net::LDAP::Filter.escape(params[:words])

    # Construct the results using a raw search. It's much, much faster that way.
    @users = User.search_as_utf8(
      scope: :one,
      filter: '(&' + words.split(' ').map { |w| "(|(givenName=*#{w}*)(sn=*#{w}*)(uid=*#{w}*))" }.join + ')',
      attributes: ['puavoId', 'puavoEduPersonPrimarySchool', 'sn', 'givenName', 'uid']
    ).map do |dn, u|
      # Non-owners might not have access to the user school information, but they can see
      # the primary school DN. Extract the school's ID from it.
      school_id = u['puavoEduPersonPrimarySchool'][0].match(/^puavoId=([^,]+)/).to_a[1]

      name = "#{u['sn'][0]}, #{u['givenName'][0]}"

      {
        'id' => u['puavoId'][0],
        'uid' => u['uid'][0],
        'school_id' => school_id,
        'school_dn' => u['puavoEduPersonPrimarySchool'][0],
        'name' => name,
        'sortable_name' => name.downcase,
      }
    end.sort do |a, b|
      a['sortable_name'] <=> b['sortable_name']
    end

    @owner = current_user.organisation_owner?
    @admin = Array(current_user.puavoAdminOfSchool || []).map(&:to_s).to_set

    @schools = School.search_as_utf8(
      scope: :one,
      attributes: ['puavoId', 'displayName']
    ).collect do |dn, v|
      [v['puavoId'][0], v['displayName'][0]]
    end.to_h

    respond_to do |format|
      if @users.length == 0
        format.html { render inline: "<p>#{t('search.no_matches')}</p>" }
      else
        format.html { render :user_search, layout: false }
      end
    end
  rescue StandardError => e
    logger.error(e)
    render inline: "<p class=\"searchError\">#{t('search.failed')}</p>"
  end

  private

  def group_params
    params.require(:group).permit(
      :displayName,
      :cn,
      :puavoExternalId,
      :puavoEduGroupType,
      :puavoNotes
    ).to_hash
  end

  def get_group(id)
    begin
      Group.find(id)
    rescue ActiveLdap::EntryNotFound => e
      flash[:alert] = t('flash.invalid_group_id', id: id)
      redirect_to groups_path(@school)
      nil
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

    members.sort!{ |a, b| ("#{a['givenName']} #{a['sn']}").downcase <=> ("#{a['givenName']} #{a['sn']}").downcase }.reverse

    return members, num_hidden
  end
end
