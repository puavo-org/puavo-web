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
      format.json  { render :json => @schools }
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

  # GET /schools/:school_id/image
  def image
    @school = School.find(params[:id])

    send_data @school.jpegPhoto, :disposition => 'inline', :type => "image/jpeg"
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
        flash[:success] = t('flash.added', :item => t('activeldap.models.school'))
        format.html { redirect_to( school_path(@school) ) }
        format.xml  { render :xml => @school, :status => :created, :location => @school }
      else
        flash[:error] = t('flash.create_failed', :model => t('activeldap.models.school').downcase )
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
        flash[:success] = t('flash.updated', :item => t('activeldap.models.school'))
        format.html { redirect_to(@school) }
        format.xml  { head :ok }
      else
        flash[:error] = t('flash.save_failed', :model => t('activeldap.models.school') )
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
        flash[:error] = t('flash.school.destroyed_failed')
        format.html { redirect_to(school_path(@school)) }
        format.xml  { render :xml => @school.errors, :status => :unprocessable_entity }
      elsif @school.destroy
        flash[:success] = t('flash.destroyed', :item => t('activeldap.models.school'))
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

    respond_to do |format|
      if not Array(@user.puavoEduPersonAffiliation).include?('admin')
        # FIXME: change notice type (ERROR)
        flash[:error] = t('flash.school.wrong_user_type')
        format.html { redirect_to( admins_school_path(@school) ) }
<<<<<<< HEAD
      elsif @school.ldap_modify_operation( :add, [{"puavoSchoolAdmin" => [@user.dn.to_s]}] ) &&
          @user.ldap_modify_operation( :add, [{"puavoAdminOfSchool" => [@school.dn.to_s]}] ) &&
          SambaGroup.add_uid_to_memberUid('Domain Admins', @user.uid)
        flash[:notice] = t('flash.school.school_admin_added',
=======
      elsif @school.save && @user.save && SambaGroup.add_uid_to_memberUid('Domain Admins', @user.uid)
        flash[:success] = t('flash.school.school_admin_added',
>>>>>>> 640b712a04b192e01de01767b843abd9aac1344b
                           :displayName => @user.displayName,
                           :school_name => @school.displayName )
        format.html { redirect_to( admins_school_path(@school) ) }
      else
        # FIXME: change notice type (ERROR)
        flash[:error] = t('flash.school.save_failed')
        format.html { redirect_to( admins_school_path(@school) ) }
      end
    end
  end

  # PUT /schools/1/remove_school_admin/1
  def remove_school_admin
    @school = School.find(params[:id])
    @user = User.find(params[:user_id])

    # Delete user from the list of Domain Users if it is no in any school administrator
    if Array(@user.puavoAdminOfSchool).count < 2
      SambaGroup.delete_uid_from_memberUid('Domain Admins', @user.uid)
    end

    @school.ldap_modify_operation( :delete, [{"puavoSchoolAdmin" => [@user.dn.to_s]}] )
    @user.ldap_modify_operation( :delete, [{"puavoAdminOfSchool" => [@school.dn.to_s]}] )

    respond_to do |format|
      flash[::success] = t('flash.school.school_admin_removed',
                           :displayName => @user.displayName,
                           :school_name => @school.displayName )
      format.html { redirect_to( admins_school_path(@school) ) }
    end
  end
end
