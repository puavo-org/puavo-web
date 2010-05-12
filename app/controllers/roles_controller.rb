class RolesController < ApplicationController
  # GET /:school_id/roles
  # GET /:school_id/roles.xml
  def index
    if @school
      @roles = @school.roles
    else
      @roles = Role.all
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

    @member_groups = @role.groups
    @other_groups = Group.all.delete_if do |g| @member_groups.include?(g) end

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
        format.html { render :action => "edit" }
        format.xml  { render :xml => @role.errors, :status => :unprocessable_entity }
      end
    end
  end

  # DELETE /:school_id/roles/1
  # DELETE /:school_id/roles/1.xml
  def destroy
    @role = Role.find(params[:id])
    @role.destroy

    respond_to do |format|
      format.html { redirect_to(roles_url) }
      format.xml  { head :ok }
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
        flash[:notice] = t('flash.role.group_added_failed')
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
        flash[:notice] = t('flash.role.group_removed_failed')
        format.html { redirect_to( role_path(@school, @role) ) }
      end
    end
  end
end
