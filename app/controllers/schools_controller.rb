class SchoolsController < ApplicationController
  # GET /schools
  # GET /schools.xml
  def index
    if request.format == 'application/json'
      @schools = School.all.sort
    else
      @schools = School.all_with_permissions current_user
      @schools.sort!{|a, b| a.displayName.downcase <=> b.displayName.downcase }
    end

    # Count devices by school
    @device_counts = {}

    @schools.collect(&:dn).map.each do |dn|
      @device_counts[dn.to_s] = 0
    end

    Device.search(:filter => "(objectClass=device)", :attributes => ["puavoSchool"]).each do |d|
      next unless d[1].include?('puavoSchool')
      dn = d[1]['puavoSchool'][0]
      @device_counts[dn] += 1 if @device_counts.include?(dn)
    end

    @have_external_ids = @schools.any?{ |s| s.puavoExternalId }
    @have_school_codes = @schools.any?{ |s| s.puavoSchoolCode }

    respond_to do |format|
      if @schools.count < 2  && !current_user.organisation_owner?
        format.html { redirect_to( school_path(@schools.first) ) }
        format.json  { render :json => @schools }
      else
        format.html # index.html.erb
        format.json  { render :json => @schools }
      end
    end
  end

  # GET /schools/1
  # GET /schools/1.xml
  def show
    @school = School.find(params[:id])

    unless Puavo::CONFIG.nil?
      @devices_by_type = Device.search_as_utf8( :filter => "(puavoSchool=#{@school.dn})",
                                        :scope => :one,
                                        :attributes => ['puavoDeviceType'] ).inject({}) do |result, device|
        device_type = Puavo::CONFIG["device_types"][device.last["puavoDeviceType"].first]["label"][I18n.locale.to_s]
        result[device_type] = result[device_type].to_i + 1
        result
      end
    end

    @members = User.search_as_utf8( :filter => "(puavoSchool=#{@school.dn})",
                            :scope => :one,
                            :attributes => ['puavoEduPersonAffiliation'] )

    # get the creation and modification timestamps from LDAP operational attributes
    extra = School.find(params[:id], :attributes => ['createTimestamp', 'modifyTimestamp'])
    @school['createTimestamp'] = convert_timestamp(extra['createTimestamp'])
    @school['modifyTimestamp'] = convert_timestamp(extra['modifyTimestamp'])

    # Known image release names
    @releases = get_releases

    respond_to do |format|
      format.html # show.html.erb
      format.xml  { render :xml => @school }
      format.json  { render :json => @school }
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
    return if redirected_nonowner_user?

    @school = School.new
    @is_new_school = true

    respond_to do |format|
      format.html # new.html.erb
      format.xml  { render :xml => @school }
    end
  end

  # GET /schools/1/edit
  def edit
    @school = School.find(params[:id])
    @is_new_school = false
  end

  # POST /schools
  # POST /schools.xml
  def create
    return if redirected_nonowner_user?

    @school = School.new(school_params)

    respond_to do |format|
      if @school.save
        flash[:notice] = t('flash.added', :item => t('activeldap.models.school'))
        format.html { redirect_to( school_path(@school) ) }
        format.xml  { render :xml => @school, :status => :created, :location => @school }
      else
        flash[:alert] = t('flash.create_failed', :model => t('activeldap.models.school').downcase )
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
      if @school.update_attributes(school_params)
        flash[:notice] = t('flash.updated', :item => t('activeldap.models.school'))
        format.html { redirect_to(school_path(@school)) }
        format.xml  { head :ok }
      else
        flash[:alert] = t('flash.save_failed', :model => t('activeldap.models.school') )
        format.html { render :action => "edit" }
        format.xml  { render :xml => @school.errors, :status => :unprocessable_entity }
      end
    end
  end

  # DELETE /schools/1
  # DELETE /schools/1.xml
  def destroy
    return if redirected_nonowner_user?

    @school = School.find(params[:id])

    can_delete = true

    if @school.members.count > 0 ||
       @school.groups.count > 0 ||
       @school.boot_servers.count > 0 ||
       Device.find(:all, :attribute => "puavoSchool", :value => @school.dn).count > 0
      can_delete = false
    end

    respond_to do |format|
      if !can_delete
        flash[:alert] = t('flash.school.destroyed_failed')
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
    return if redirected_nonowner_user?

    # List of (admin) users who currently ARE the owners of this organisation
    @current_owners = Array(LdapOrganisation.current.owner).each.map { |dn| dn.to_s }.to_set

    @school = School.find(params[:id])

    # Current admin-level users in this schools
    @current_admins = []
    current_dn = Set.new

    @school.user_school_admins.each do |u|
      @current_admins << {
        user: u,
        schools: [],
      }

      current_dn << u.dn
    end

    # Users who aren't admins yet, but could be
    @available_admins = User.find(:all,
                                  :attribute => 'puavoEduPersonAffiliation',
                                  :value => 'admin')
    .delete_if do |u|
      current_dn.include?(u.dn)
    end.collect do |u|
      {
        user: u,
        schools: [],
      }
    end

    schools = {}

    @current_admins = sort_users(find_user_schools(@current_admins, schools))
    @available_admins = sort_users(find_user_schools(@available_admins, schools))

    respond_to do |format|
      format.html # admins.html.erb
    end
  end

  # PUT /schools/1/add_school_admin/1
  def add_school_admin
    return if redirected_nonowner_user?

    @school = School.find(params[:id])
    @user = User.find(params[:user_id])

    respond_to do |format|
      if not Array(@user.puavoEduPersonAffiliation).include?('admin')
        # FIXME: change notice type (ERROR)
        flash[:alert] = t('flash.school.wrong_user_type')
        format.html { redirect_to( admins_school_path(@school) ) }
      elsif  @school.add_admin(@user)
        flash[:notice] = t('flash.school.school_admin_added',
                           :displayName => @user.displayName,
                           :school_name => @school.displayName )
        format.html { redirect_to( admins_school_path(@school) ) }
      else
        # FIXME: change notice type (ERROR)
        flash[:alert] = t('flash.school.save_failed')
        format.html { redirect_to( admins_school_path(@school) ) }
      end
    end
  end

  # PUT /schools/1/remove_school_admin/1
  def remove_school_admin
    return if redirected_nonowner_user?

    @school = School.find(params[:id])
    @user = User.find(params[:user_id])

    # Delete user from the list of Domain Users if it is no in any school administrator
    if Array(@user.puavoAdminOfSchool).count < 2
      SambaGroup.delete_uid_from_memberUid('Domain Admins', @user.uid)
    end

    @school.ldap_modify_operation( :delete, [{"puavoSchoolAdmin" => [@user.dn.to_s]}] )
    @user.ldap_modify_operation( :delete, [{"puavoAdminOfSchool" => [@school.dn.to_s]}] )

    respond_to do |format|
      flash[:notice] = t('flash.school.school_admin_removed',
                           :displayName => @user.displayName,
                           :school_name => @school.displayName )
      format.html { redirect_to( admins_school_path(@school) ) }
    end
  end

  # GET /schools/1/wlan
  def wlan
    return unless can_edit_wlans?

    @school = School.find(params[:id])

    respond_to do |format|
      format.html
    end
  end

  # PUT /schools/1/wlan/update
  def wlan_update
    return unless can_edit_wlans?

    @school = School.find(params[:id])

    @school.update_wlan_attributes(params)
    @school.puavoWlanChannel = params[:school][:puavoWlanChannel]

    respond_to do |format|
      if @school.save
        flash[:notice] = t('flash.wlan_updated')
        format.html { redirect_to( wlan_school_path ) }
      else
        flash[:alert] = t('flash.wlan_save_failed', :error => @school.errors["puavoWlanSSID"].first )
        format.html { render :action => "wlan" }
      end
    end
  end

  private
    def sort_users(l)
      l.sort! do |a, b|
        ((a[:user]["givenName"] || "") + (a[:user]["sn"] || "")).downcase <=>
          ((b[:user]["givenName"] || "") + (b[:user]["sn"] || "")).downcase
      end
    end

    def find_user_schools(l, schools_cache)
      l.each do |o|
        Array(o[:user].puavoSchool).each do |dn|
          schools_cache[dn] = School.find(dn) unless schools_cache.include?(dn)
          o[:schools] << schools_cache[dn]
        end

        # sort the schools alphabetically
        o[:schools].sort!{ |a, b| a.displayName.downcase <=> b.displayName.downcase }
      end
    end

    def school_params
      s = params.require(:school).permit(
        :displayName,
        :cn,
        :puavoSchoolCode,
        :puavoNamePrefix,
        :puavoSchoolHomePageURL,
        :description,
        :telephoneNumber,
        :facsimileTelephoneNumber,
        :l,
        :street,
        :postOfficeBox,
        :postalAddress,
        :postalCode,
        :st,
        :puavoLocale,
        :image,
        :puavoExternalId,
        :puavoAllowGuest,
        :puavoPersonalDevice,
        :puavoAutomaticImageUpdates,
        :puavoDeviceImage,
        :puavoTag,
        :puavoConf,
        :puavoDeviceAutoPowerOffMode,
        :puavoDeviceOnHour,
        :puavoDeviceOffHour,
        :puavoBillingInfo=>[],
        :puavoImageSeriesSourceURL=>[],
        :fs=>[],
        :path=>[],
        :mountpoint=>[],
        :options=>[]
      ).to_hash


      # deduplicate arrays, as LDAP really does not like duplicate entries...
      s["puavoTag"] = s["puavoTag"].split.uniq.join(' ') if s.key?("puavoTag")
      s["puavoBillingInfo"].uniq! if s.key?("puavoBillingInfo")
      s["puavoImageSeriesSourceURL"].uniq! if s.key?("puavoImageSeriesSourceURL")

      strip_img(s)

      clear_puavoconf(s)

      s['displayName'].strip! if s.include?('displayName')
      s['cn'].strip! if s.include?('cn')

      return s
    end

    # Allow admins edit WLANs in schools they're admins of, but nowhere else.
    # No restrictions for owners.
    def can_edit_wlans?
      return true if is_owner?

      admin_in =  Array(current_user.puavoAdminOfSchool || []).collect { |dn| dn.rdns[0]["puavoId"].to_i }

      return true if admin_in.include?(@school.id.to_i)

      flash[:alert] = t('flash.you_must_be_an_owner')
      redirect_to school_path(current_user.primary_school)
      return false
    end

end
