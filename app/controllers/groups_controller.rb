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

  def get_school_groups_list
    # The "requested" parameter is ignored here on purpose. There are only few columns,
    # just get them all every time.
    attributes = GroupsHelper.convert_requested_group_column_names([])

    raw = Group.search_as_utf8(:filter => "(puavoSchool=#{@school.dn})",
                               :scope => :one,
                               :attributes => attributes)

    groups = []

    # Convert the raw data into something we can easily parse in JavaScript
    raw.each do |dn, grp|
      g = {}

      g.merge!(GroupsHelper.build_common_group_properties(grp, []))
      g[:link] = group_path(@school, grp['puavoId'][0])
      g[:school_id] = @school.id.to_i

      groups << g
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
      group.delete
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
      new_list = List.new(@group.members.map{ |u| u.id })
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
    return if redirected_nonowner_user?

    @group = get_group(params[:id])
    return if @group.nil?

    if @group.members.empty?
      flash[:notice] = t('flash.group.empty_group')
      redirect_to group_path(@school, @group)
      return
    end

    now = Time.now.utc
    count = 0

    @group.members.each do |u|
      begin
        if u.puavoRemovalRequestTime.nil?
          u.puavoRemovalRequestTime = now
          u.puavoLocked = true
          u.save
          count += 1
        end
      rescue StandardError => e
      end
    end

    respond_to do |format|
      flash[:notice] = t('flash.group.members_marked', :count => count)
      format.html { redirect_to group_path(@school, @group) }
    end
  end

  # PUT /:school_id/groups/:group_id/unmark_group_members_deletion
  def unmark_group_members_deletion
    return if redirected_nonowner_user?

    @group = get_group(params[:id])
    return if @group.nil?

    if @group.members.empty?
      flash[:notice] = t('flash.group.empty_group')
      redirect_to group_path(@school, @group)
      return
    end

    count = 0

    @group.members.each do |u|
      begin
        if u.puavoRemovalRequestTime
          u.puavoRemovalRequestTime = nil
          u.save
          count += 1
        end
      rescue StandardError => e
      end
    end

    respond_to do |format|
      flash[:notice] = t('flash.group.members_unmarked', :count => count)
      format.html { redirect_to group_path(@school, @group) }
    end
  end

  # PUT /:school_id/groups/:group_id/lock_all_members
  def lock_all_members
    return if redirected_nonowner_user?

    @group = get_group(params[:id])
    return if @group.nil?

    if @group.members.empty?
      flash[:notice] = t('flash.group.empty_group')
      redirect_to group_path(@school, @group)
      return
    end

    count = 0

    @group.members.each do |u|
      begin
        unless u.puavoLocked
          u.puavoLocked = true
          u.save
          count += 1
        end
      rescue StandardError => e
      end
    end

    respond_to do |format|
      flash[:notice] = t('flash.group.members_locked', :count => count)
      format.html { redirect_to group_path(@school, @group) }
    end
  end

  # PUT /:school_id/groups/:group_id/unlock_all_members
  def unlock_all_members
    return if redirected_nonowner_user?

    @group = get_group(params[:id])
    return if @group.nil?

    if @group.members.empty?
      flash[:notice] = t('flash.group.empty_group')
      redirect_to group_path(@school, @group)
      return
    end

    count = 0

    @group.members.each do |u|
      begin
        if u.puavoLocked
          u.puavoLocked = nil
          u.save
          count += 1
        end
      rescue StandardError => e
      end
    end

    respond_to do |format|
      flash[:notice] = t('flash.group.members_unlocked', :count => count)
      format.html { redirect_to group_path(@school, @group) }
    end
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

  def find_groupless_users
    @users = []

    @school.members.each do |m|
      @users << m if m.groups.empty?
    end

    # sort by name
    @users.sort!{|a, b| a.displayName.downcase <=> b.displayName.downcase }

    respond_to do |format|
      format.html { render :action => "groupless_users" }
    end
  end

  def mark_groupless_users_for_deletion
    ok = 0
    failed = 0
    now = Time.now.utc

    @school.members.each do |m|
      next unless m.groups.empty?
      next if m.puavoRemovalRequestTime

      begin
        m.puavoRemovalRequestTime = now
        m.puavoLocked = true
        m.save!
        ok += 1
      rescue StandardError => e
        failed += 1
      end
    end

    respond_to do |format|
      flash[:notice] = t('flash.group.groupless_marked', :ok => ok, :failed => failed)
      format.html { redirect_to groups_path(@school) }
    end
  end

  # Remove all members from a group
  def remove_all_members
    @group = get_group(params[:id])
    return if @group.nil?

    members = @group.members
    ok = true

    members.each do |m|
      begin
        @group.remove_user(m)
      rescue StandardError => e
        puts "===> Could not remove member #{m} from group #{@group}: #{e}"
        ok = false
      end
    end

    respond_to do |format|
      flash[:notice] = ok ? t('flash.group.group_emptied_ok') : t('flash.group.group_emptied_failed')
      format.html { redirect_to group_path(@school, @group) }
    end
  end

  # GET /:school_id/groups/:group_id/get_members_as_csv
  def get_members_as_csv
    return if redirected_nonowner_user?

    @group = get_group(params[:id])
    return if @group.nil?

    output = CSV.generate(:headers => true, :force_quotes => true) do |csv|
      csv << ['puavoid', 'username', 'firstname', 'lastname']

      @group.members.each do |m|
        csv << [m.id, m.uid, m.givenName, m.surname]
      end
    end

    filename = "#{current_organisation.organisation_key}_#{@group.cn}_members_#{Time.now.strftime("%Y%m%d_%H%M%S")}.csv"

    send_data(output,
              :filename => filename,
              :type => 'text/csv',
              :disposition => 'attachment' )
  end

  def add_user
    @group = Group.find(params[:id])
    @user = User.find(params[:user_id])

    Group.ldap_modify_operation(@group.dn, :add, [{ "memberUid" => [@user.uid]},
                                                  { "member" => [@user.dn.to_s] }])

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

end
