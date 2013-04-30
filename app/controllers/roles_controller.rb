class RolesController < ApplicationController
  # GET /:school_id/roles
  # GET /:school_id/roles.xml
  def index
    if @school
      @roles = @school.roles.sort
    else
      @roles = Role.all.sort
    end

    respond_to do |format|
      format.html # index.html.erb
      format.xml  { render :xml => @roles }
    end
  end

  # GET /:school_id/roles/1
  # GET /:school_id/roles/1.xml
  def show
    @role = Role.find(params[:id])

    @member_groups = @role.groups.sort
    @other_groups = Group.all.delete_if do |g| @member_groups.include?(g) end.sort

    respond_to do |format|
      format.html # show.html.erb
      format.xml  { render :xml => @role }
    end
  end

  # GET /:school_id/roles/new
  # GET /:school_id/roles/new.xml
  def new
    @role = Role.new

    respond_to do |format|
      format.html # new.html.erb
      format.xml  { render :xml => @role }
    end
  end

  # GET /:school_id/roles/1/edit
  def edit
    @role = Role.find(params[:id])
  end

  # POST /:school_id/roles
  # POST /:school_id/roles.xml
  def create
    @role = Role.new(params[:role])

    @role.puavoSchool = @school.dn
    respond_to do |format|
      if @role.save
        flash[:notice] = t('flash.added', :item => t('activeldap.models.role'))
        format.html { redirect_to( role_path(@school, @role) ) }
        format.xml  { render :xml => @role, :status => :created, :location => @role }
      else
        flash[:alert] = t('flash.role.create_failed')
        format.html { render :action => "new" }
        format.xml  { render :xml => @role.errors, :status => :unprocessable_entity }
      end
    end
  end

  # PUT /:school_id/roles/1
  # PUT /:school_id/roles/1.xml
  def update
    @role = Role.find(params[:id])

    respond_to do |format|
      if @role.update_attributes(params[:role])
        flash[:notice] = t('flash.updated', :item => t('activeldap.models.role'))
        format.html { redirect_to( role_path(@school, @role) ) }
        format.xml  { head :ok }
      else
        flash[:alert] = t('flash.role.save_failed')
        format.html { render :action => "edit" }
        format.xml  { render :xml => @role.errors, :status => :unprocessable_entity }
      end
    end
  end

  # DELETE /:school_id/roles/1
  # DELETE /:school_id/roles/1.xml
  def destroy
    @role = Role.find(params[:id])

    respond_to do |format|
      if @role.members.count > 0
        flash[:alert] = t('flash.role.destroyed_failed', :name => @role.displayName)
        format.html { redirect_to(roles_path(@school)) }
      elsif @role.destroy
        flash[:notice] = t('flash.destroyed', :item => t('activeldap.models.role'))
        format.html { redirect_to(roles_url) }
      end
    end
  end

  def add_group
    @group = Group.find(params[:group_id])
    @role = Role.find(params[:id])

    respond_to do |format|
      if @role.groups << @group
        @role.update_associations
        flash[:notice] = t('flash.role.group_added')
        format.html { redirect_to( role_path(@school, @role) ) }
      else
        flash[:alert] = t('flash.role.group_added_failed')
        format.html { redirect_to( role_path(@school, @role) ) }
      end
    end
  end

  def remove_group
    @group = Group.find(params[:group_id])
    @role = Role.find(params[:id])

    respond_to do |format|
      if @role.groups.delete(@group)
        @role.update_associations
        flash[:notice] = t('flash.role.group_removed')
        format.html { redirect_to( role_path(@school, @role) ) }
      else
        flash[:alert] = t('flash.role.group_removed_failed')
        format.html { redirect_to( role_path(@school, @role) ) }
      end
    end
  end

  # GET /:school_id/roles/:id/select_school
  def select_school
    @role = Role.find(params[:id])
    @schools = School.all_with_permissions current_user

    respond_to do |format|
      format.html
    end
  end

  # POST /:school_id/roles/:id/select_role
  def select_role
    @role = Role.find(params[:id])
    @new_school = School.find(params[:new_school])
    @roles = @new_school.roles.sort
    @users = @role.members

    respond_to do |format|
      format.html
    end
  end
end
