class SchoolsController < ApplicationController
  # GET /schools
  # GET /schools.xml
  def index
    @schools = School.all_with_permissions

    respond_to do |format|
      if @schools.count < 2  && !organisation_owner?
        format.html { redirect_to( school_path(@schools.first) ) }
      else
        format.html # index.html.erb
      end
      format.xml  { render :xml => @schools }
    end
  end

  # GET /schools/1
  # GET /schools/1.xml
  def show
    @school = School.find(params[:id])

    unless Puavo::DEVICE_CONFIG.nil?
      @devices_by_type = Device.search( :filter => "(puavoSchool=#{@school.dn})",
                                        :scope => :one,
                                        :attributes => ['puavoDeviceType'] ).inject({}) do |result, device|
        device_type = Puavo::DEVICE_CONFIG["device_types"][device.last["puavoDeviceType"].to_s]["label"][I18n.locale.to_s] 
        result[device_type] = result[device_type].to_i + 1
        result
      end
    end

    @members = User.search( :filter => "(puavoSchool=#{@school.dn})",
                            :scope => :one,
                            :attributes => ['puavoEduPersonAffiliation'] )

    respond_to do |format|
      format.html # show.html.erb
      format.xml  { render :xml => @school }
    end
  end

  # GET /schools/new
  # GET /schools/new.xml
  def new
    @school = School.new

    respond_to do |format|
      format.html # new.html.erb
      format.xml  { render :xml => @school }
    end
  end

  # GET /schools/1/edit
  def edit
    @school = School.find(params[:id])
  end

  # POST /schools
  # POST /schools.xml
  def create
    @school = School.new(params[:school])

    respond_to do |format|
      if @school.save
        flash[:notice] = t('flash.added', :item => t('activeldap.models.school'))
        format.html { redirect_to( school_path(@school) ) }
        format.xml  { render :xml => @school, :status => :created, :location => @school }
      else
        flash[:notice] = t('flash.create_failed', :model => t('activeldap.models.school').downcase )
        format.html { render :action => "new" }
        format.xml  { render :xml => @school.errors, :status => :unprocessable_entity }
      end
    end
  end

  # PUT /schools/1
  # PUT /schools/1.xml
  def update
    @school = School.find(params[:id])

    respond_to do |format|
      if @school.update_attributes(params[:school])
        flash[:notice] = t('flash.updated', :item => t('activeldap.models.school'))
        format.html { redirect_to(@school) }
        format.xml  { head :ok }
      else
        flash[:notice] = t('flash.save_failed', :model => t('activeldap.models.school') )
        format.html { render :action => "edit" }
        format.xml  { render :xml => @school.errors, :status => :unprocessable_entity }
      end
    end
  end

  # DELETE /schools/1
  # DELETE /schools/1.xml
  def destroy
    @school = School.find(params[:id])

    respond_to do |format|
      if @school.members.count > 0 || @school.roles.count > 0 || @school.groups.count > 0
        flash[:notice] = t('flash.school.destroyed_failed')
        format.html { redirect_to(school_path(@school)) }
        format.xml  { render :xml => @school.errors, :status => :unprocessable_entity }
      elsif @school.destroy
        flash[:notice] = t('flash.destroyed', :item => t('activeldap.models.school'))
        format.html { redirect_to(schools_url) }
        format.xml  { head :ok }
      else
        format.html { render :action => "show" }
        format.xml  { render :xml => @school.errors, :status => :unprocessable_entity }
      end
    end
  end

  # GET /schools/1/admins
  def admins
    @school = School.find(params[:id])
    @school_admins = @school.user_school_admins
    @allowed_school_admins = User.find(:all,
                                       :attribute => 'puavoEduPersonAffiliation',
                                       :value => 'admin').delete_if do |u|
      @school_admins.include?(u)
    end

    respond_to do |format|
      format.html # admins.html.erb
    end
  end

  # PUT /schools/1/add_school_admin/1
  def add_school_admin
    @school = School.find(params[:id])
    @user = User.find(params[:user_id])

    @school.puavoSchoolAdmin = Array(@school.puavoSchoolAdmin).push @user.dn
    @user.puavoAdminOfSchool = Array(@user.puavoAdminOfSchool).push @school.dn

    respond_to do |format|
      if not Array(@user.puavoEduPersonAffiliation).include?('admin')
        # FIXME: change notice type (ERROR)
        flash[:notice] = t('flash.school.wrong_user_type')
        format.html { redirect_to( admins_school_path(@school) ) }
      elsif @school.save && @user.save && SambaGroup.add_uid_to_memberUid('Domain Admins', @user.uid)
        flash[:notice] = t('flash.school.school_admin_added',
                           :displayName => @user.displayName,
                           :school_name => @school.displayName )
        format.html { redirect_to( admins_school_path(@school) ) }
      else
        # FIXME: change notice type (ERROR)
        flash[:notice] = t('flash.school.save_failed')
        format.html { redirect_to( admins_school_path(@school) ) }
      end
    end
  end

  # PUT /schools/1/remove_school_admin/1
  def remove_school_admin
    @school = School.find(params[:id])
    @user = User.find(params[:user_id])

    @school.puavoSchoolAdmin = Array(@school.puavoSchoolAdmin).delete_if do |admin_dn|
      admin_dn ==  @user.dn
    end
    @user.puavoAdminOfSchool = Array(@user.puavoAdminOfSchool).delete_if do |school_dn|
      school_dn ==  @school.dn
    end

    respond_to do |format|
      if @school.save && @user.save && SambaGroup.delete_uid_from_memberUid('Domain Admins', @user.uid)
        flash[:notice] = t('flash.school.school_admin_removed',
                           :displayName => @user.displayName,
                           :school_name => @school.displayName )
        format.html { redirect_to( admins_school_path(@school) ) }
      else
        # FIXME: change notice type (ERROR)
        flash[:notice] = t('flash.school.save_failed')
        format.html { redirect_to( admins_school_path(@school) ) }
      end
    end
  end
end
