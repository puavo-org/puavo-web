class GroupsController < ApplicationController

  # GET /:school_id/groups/:id/members
  def members
    @group = Group.find(params[:id])

    @members = @group.members

    respond_to do |format|
      format.json  { render :json => @members }
    end
  end

  # GET /:school_id/groups
  # GET /:school_id/groups.xml
  def index
    if @school
      @groups = @school.groups.sort
    else
      @groups = Group.all.sort
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

  # GET /:school_id/groups/1
  # GET /:school_id/groups/1.xml
  def show
    @group = Group.find(params[:id])

    @members = @group.members

    @roles = @group.roles.sort
    @other_roles = Role.all.delete_if do |p| @roles.include?(p) end

    respond_to do |format|
      format.html # show.html.erb
      format.xml  { render :xml => @group }
    end
  end

  # GET /:school_id/groups/new
  # GET /:school_id/groups/new.xml
  def new
    @group = Group.new

    respond_to do |format|
      format.html # new.html.erb
      format.xml  { render :xml => @group }
    end
  end

  # GET /:school_id/groups/1/edit
  def edit
    @group = Group.find(params[:id])
  end

  # POST /:school_id/groups
  # POST /:school_id/groups.xml
  def create
    @group = Group.new(params[:group])

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
    @group = Group.find(params[:id])

    respond_to do |format|
      if @group.update_attributes(params[:group])
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
    @group = Group.find(params[:id])

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

  def add_role
    @group = Group.find(params[:id])
    @role = Role.find(params[:role_id])

    respond_to do |format|
      if @role.groups << @group && @group.save
        @role.update_associations
        flash[:notice] =  t('flash.group.role_added')
        format.html { redirect_to( group_path(@school, @group) ) }
      else
        flash[:notice] = t('flash.group.role_added')
        format.html { redirect_to( group_path(@school, @group) ) }
      end
    end
  end

  def delete_role
    @group = Group.find(params[:id])
    @role = Role.find(params[:role_id])

    respond_to do |format|
      if @role.groups.delete(@group) && @group.save
        @role.update_associations
        flash[:notice] =  t('flash.group.role_removed')
        format.html { redirect_to( group_path(@school, @group) ) }
      else
        flash[:alert] =  t('flash.group.role_removed_failed')
        format.html { redirect_to( group_path(@school, @group) ) }
      end
    end
  end

  def user_search
    @group = Group.find(params[:id])

    @users = User.words_search_and_sort_by_name(
      ["sn", "givenName", "uid"],
      lambda{ |v| "#{v['sn'].first} #{v['givenName'].first}" },
      lambda { |w| "(|(givenName=*#{w}*)(sn=*#{w}*)(uid=*#{w}*))" },
      params[:words] )

    @schools = Hash.new
    School.search_as_utf8( :scope => :one,
                   :attributes => ["puavoId", "displayName"] ).map do |dn, v|
      @schools[v["puavoId"].first] = v["displayName"].first
    end

    respond_to do |format|
      if @users.length == 0
        format.html { render :inline => '' }
      else
        format.html { render :user_search, :layout => false }
      end
    end

  end
end
