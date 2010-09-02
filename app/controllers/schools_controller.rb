class SchoolsController < ApplicationController
  # GET /schools
  # GET /schools.xml
  def index
    @schools = School.all

    respond_to do |format|
      format.html # index.html.erb
      format.xml  { render :xml => @schools }
    end
  end

  # GET /schools/1
  # GET /schools/1.xml
  def show
    @school = School.find(params[:id])

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
        flash[:notice] = 'School was successfully created.'
        format.html { redirect_to( school_path(@school) ) }
        format.xml  { render :xml => @school, :status => :created, :location => @school }
      else
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
        flash[:notice] = 'School was successfully updated.'
        format.html { redirect_to(@school) }
        format.xml  { head :ok }
      else
        format.html { render :action => "edit" }
        format.xml  { render :xml => @school.errors, :status => :unprocessable_entity }
      end
    end
  end

  # DELETE /schools/1
  # DELETE /schools/1.xml
  def destroy
    @school = School.find(params[:id])
    @school.destroy

    respond_to do |format|
      format.html { redirect_to(schools_url) }
      format.xml  { head :ok }
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

    respond_to do |format|
      if not Array(@user.puavoEduPersonAffiliation).include?('admin')
        # FIXME: change notice type (ERROR)
        flash[:notice] = t('flash.school.wrong_user_type')
        format.html { redirect_to( admins_school_path(@school) ) }
      elsif @school.save
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

    respond_to do |format|
      if @school.save
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
