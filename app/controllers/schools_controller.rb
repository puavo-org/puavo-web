require 'set'

class SchoolsController < ApplicationController
  include Puavo::Integrations
  include Puavo::PuavomenuEditor

  # GET /schools
  # GET /schools.xml
  def index
    if request.format == 'application/json'
      @schools = School.all.sort
    else
      @schools = School.all_with_permissions current_user
    end

    @data = {
      bootservers: {},
      schools: [],
    }

    @is_owner = is_owner?

    if @is_owner || @schools.count > 1
      # Count groups and devices by school
      @group_counts = {}
      @device_counts = {}

      @schools.collect(&:dn).map.each do |dn|
        @group_counts[dn.to_s] = 0
        @device_counts[dn.to_s] = 0
      end

      Group.search(filter: '(objectClass=puavoEduGroup)', attributes: ['puavoSchool']).each do |g|
        dn = g[1]['puavoSchool'][0]
        @group_counts[dn] += 1 if @group_counts.include?(dn)
      end

      Device.search(filter: '(objectClass=device)', attributes: ['puavoSchool']).each do |d|
        next unless d[1].include?('puavoSchool')
        dn = d[1]['puavoSchool'][0]
        @device_counts[dn] += 1 if @device_counts.include?(dn)
      end

      @have_external_ids = @schools.any? { |s| s.puavoExternalId }
      @have_school_codes = @schools.any? { |s| s.puavoSchoolCode }

      releases = get_releases()

      @schools.each do |s|
        bs_names = []

        s.boot_servers.each do |bs|
          bs_names << bs.puavoHostname

          unless @data[:bootservers].include?(bs.puavoHostname)
            @data[:bootservers][bs.puavoHostname] = server_path(bs)
          end
        end

        extra = School.find(s.id, attributes: %w[createTimestamp modifyTimestamp])

        @data[:schools] << {
          id: s.id.to_i,
          name: s.displayName,
          prefix: s.cn,
          eid: s.puavoExternalId,
          school_code: s.puavoSchoolCode,
          school_oid: s.puavoSchoolOID,
          num_members: Array(s.memberUid || []).count,
          num_groups: @group_counts[s.dn.to_s],
          num_devices: @device_counts[s.dn.to_s],
          boot_servers: bs_names,
          tags: Array(s.puavoTag),
          locale: s.puavoLocale,
          timezone: s.puavoTimezone,
          conf: s.puavoConf.nil? ? [] : JSON.parse(s.puavoConf).collect { |k, v| "#{k} = #{v}" },
          integrations: get_school_integrations_by_type(@organisation_name, s.id),
          desktop_image: Puavo::Helpers::get_release_name(s.puavoDeviceImage, releases),
          image_series: Array(s.puavoImageSeriesSourceURL || []),
          allow_guest: s.puavoAllowGuest == true,
          personal_device: s.puavoPersonalDevice == true,
          auto_updates: s.puavoAutomaticImageUpdates == true,
          autopower_mode: s.puavoDeviceAutoPowerOffMode,
          autopower_on: s.puavoDeviceOnHour,
          autopower_off: s.puavoDeviceOffHour,
          description: s.description,
          notes: s.puavoNotes ? s.puavoNotes.gsub("\r", '').split("\n") : nil,
          link: school_path(s),
        }
      end
    end

    respond_to do |format|
      if @schools.count < 2 && !current_user.organisation_owner?
        format.html { redirect_to(school_path(@schools.first)) }
        format.json { render json: @schools }
      else
        format.html # index.html.erb
        format.json { render json: @schools }
      end
    end
  end

  # GET /schools/1
  # GET /schools/1.xml
  def show
    @school = School.find(params[:id])

    # Count devices by type
    @devices_by_type =
      Device.search_as_utf8(filter: "(puavoSchool=#{@school.dn})", scope: :one, attributes: ['puavoDeviceType'])
        .collect { |_, d| d['puavoDeviceType'] }
        .flatten
        .tally
        .transform_keys { |k| t("host.types.#{k}") }

    # Count school members by type
    @members_by_type =
      User.search_as_utf8(filter: "(puavoSchool=#{@school.dn})", scope: :one, attributes: ['puavoEduPersonAffiliation'])
          .collect { |_, u| u['puavoEduPersonAffiliation'] }
          .flatten
          .tally

    # Get extra timestamps from LDAP operational attributes
    timestamps = School.search_as_utf8(
      filter: "(puavoId=#{@school.id})",
      attributes: %w[createTimestamp modifyTimestamp]
    )[0][1]

    @created = Puavo::Helpers.ldap_time_string_to_utc_time(timestamps['createTimestamp'])
    @modified = Puavo::Helpers.ldap_time_string_to_utc_time(timestamps['modifyTimestamp'])

    # Known image release names
    @releases = get_releases

    make_puavomenu_preview(@school.puavoMenuData)

    @full_puavoconf = list_all_puavoconf_values(LdapOrganisation.current.puavoConf, @school.puavoConf, nil)

    @can_edit = is_owner? || current_user.has_admin_permission?(:school_edit)

    respond_to do |format|
      format.html # show.html.erb
      format.xml { render xml: @school }
      format.json { render json: @school }
    end
  end

  # GET /schools/:school_id/image
  def image
    @school = School.find(params[:id])

    send_data @school.jpegPhoto, disposition: 'inline', type: 'image/jpeg'
  end

  # GET /schools/new
  # GET /schools/new.xml
  def new
    return if redirected_nonowner_user?

    @school = School.new
    @is_new_school = true

    respond_to do |format|
      format.html # new.html.erb
      format.xml { render xml: @school }
    end
  end

  # GET /schools/1/edit
  def edit
    @school = School.find(params[:id])
    @is_new_school = false

    @releases = get_releases
    @image_filenames_by_release = DevicesHelper.group_image_filenames_by_release(@releases)

    unless is_owner? || current_user.has_admin_permission?(:school_edit)
      flash[:alert] = t('flash.you_must_be_an_owner')
      redirect_to school_path(@school)
      return
    end
  end

  # POST /schools
  # POST /schools.xml
  def create
    return if redirected_nonowner_user?

    @school = School.new(school_params)

    respond_to do |format|
      if @school.save
        flash[:notice] = t('flash.added', item: t('activeldap.models.school'))
        format.html { redirect_to(school_path(@school)) }
        format.xml { render xml: @school, status: :created, location: @school }
      else
        flash[:alert] = t('flash.create_failed', model: t('activeldap.models.school').downcase)
        format.html { render action: 'new' }
        format.xml { render xml: @school.errors, status: :unprocessable_entity }
      end
    end
  end

  # PUT /schools/1
  # PUT /schools/1.xml
  def update
    @school = School.find(params[:id])

    unless is_owner? || current_user.has_admin_permission?(:school_edit)
      flash[:alert] = t('flash.you_must_be_an_owner')
      redirect_to school_path(@school)
      return
    end

    respond_to do |format|
      if @school.update_attributes(school_params)
        flash[:notice] = t('flash.updated', item: t('activeldap.models.school'))
        format.html { redirect_to(school_path(@school)) }
        format.xml { head :ok }
      else
        flash[:alert] = t('flash.save_failed', model: t('activeldap.models.school'))
        format.html { render action: 'edit' }
        format.xml { render xml: @school.errors, status: :unprocessable_entity }
      end
    end
  end

  # DELETE /schools/1
  # DELETE /schools/1.xml
  def destroy
    return if redirected_nonowner_user?

    @school = School.find(params[:id])

    # Is the school empty?
    can_delete = true

    if @school.members.count > 0 ||
       @school.groups.count > 0 ||
       @school.boot_servers.count > 0 ||
       Device.find(:all, attribute: 'puavoSchool', value: @school.dn).count > 0
      can_delete = false
    end

    if can_delete
      # Remove school admins
      User.find(:all, attribute: 'puavoAdminOfSchool', value: @school.dn).each do |user|
        @school.remove_admin(user)
      end
    end

    respond_to do |format|
      if !can_delete
        flash[:alert] = t('flash.school.destroyed_failed')
        format.html { redirect_to(school_path(@school)) }
        format.xml { render xml: @school.errors, status: :unprocessable_entity }
      elsif @school.destroy
        flash[:notice] = t('flash.destroyed', item: t('activeldap.models.school'))
        format.html { redirect_to(schools_url) }
        format.xml { head :ok }
      else
        format.html { render action: 'show' }
        format.xml { render xml: @school.errors, status: :unprocessable_entity }
      end
    end
  end

  # GET /schools/1/admins
  def admins
    return if redirected_nonowner_user?

    # Highlight organisation owners
    @current_owners = owners_set()

    # Make a list of users who are currently admins of this school
    @school = School.find(params[:id])
    @current_admins = []

    @school.user_school_admins.each do |user|
      @current_admins << {
        user: user,
        sort_name: "#{user['givenName']} #{user['sn']}".downcase
      }
    end

    current_admins_dn = @current_admins.collect { |o| o[:user].dn.to_s }.to_set.freeze

    # Then make a list of admin users who aren't yet admining this school
    @available_admins = User.find(:all, attribute: 'puavoEduPersonAffiliation', value: 'admin')
      .reject { |u| current_admins_dn.include?(u.dn.to_s) }
      .collect do |user|
      {
        user: user,
        sort_name: "#{user['givenName']} #{user['sn']}".downcase,
      }
    end

    # Sort both lists alphabetically by name
    @current_admins.sort! { |a, b| a[:sort_name] <=> b[:sort_name] }
    @available_admins.sort! { |a, b| a[:sort_name] <=> b[:sort_name] }

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
        flash[:alert] = t('flash.school.wrong_user_type')
        format.html { redirect_to(admins_school_path(@school)) }
      elsif @school.add_admin(@user)
        flash[:notice] = t('flash.school.school_admin_added', displayName: @user.displayName, school_name: @school.displayName)
        format.html { redirect_to(admins_school_path(@school)) }
      else
        flash[:alert] = t('flash.school.save_failed')
        format.html { redirect_to(admins_school_path(@school)) }
      end
    end
  end

  # PUT /schools/1/remove_school_admin/1
  def remove_school_admin
    return if redirected_nonowner_user?

    @school = School.find(params[:id])
    @user = User.find(params[:user_id])

    @school.remove_admin(@user)

    respond_to do |format|
      flash[:notice] = t('flash.school.school_admin_removed', displayName: @user.displayName, school_name: @school.displayName)
      format.html { redirect_to(admins_school_path(@school)) }
    end
  end

  # GET /schools/1/wlan
  def wlan
    @school = School.find(params[:id])

    unless can_edit_wlans?
      flash[:alert] = t('flash.you_must_be_an_owner')
      redirect_to school_path(current_user.primary_school)
      return
    end

    respond_to do |format|
      format.html
    end
  end

  # PUT /schools/1/wlan/update
  def wlan_update
    @school = School.find(params[:id])

    unless can_edit_wlans?
      flash[:alert] = t('flash.you_must_be_an_owner')
      redirect_to school_path(current_user.primary_school)
      return
    end

    @school.update_wlan_attributes(params)
    @school.puavoWlanChannel = params[:school][:puavoWlanChannel]

    respond_to do |format|
      if @school.save
        flash[:notice] = t('flash.wlan_updated')
        format.html { redirect_to(wlan_school_path) }
      else
        flash[:alert] = t('flash.wlan_save_failed', error: @school.errors['puavoWlanSSID'].first)
        format.html { render action: 'wlan' }
      end
    end
  end

  def edit_puavomenu
    @school = School.find(params[:id])

    unless @pme_enabled
      flash[:error] = 'Puavomenu Editor has not been enabled in this organisation'
      return redirect_to(school_path(@school))
    end

    @pme_mode = :school

    @menudata = load_menudata(@school.puavoMenuData)
    @conditions = get_conditions

    respond_to do |format|
      format.html { render 'puavomenu_editor/puavomenu_editor' }
    end
  end

  def save_puavomenu
    save_menudata do |menudata, response|
      @school = School.find(params[:id])

      @school.puavoMenuData = menudata.to_json
      @school.save!

      response[:redirect] = school_puavomenu_path(@school)
    end
  end

  def clear_puavomenu
    @school = School.find(params[:id])
    @school.puavoMenuData = nil
    @school.save!

    flash[:notice] = t('flash.puavomenu_editor.cleared')
    redirect_to(school_path(@school))
  end

  private

  def school_params
    s = params.require(:school).permit(
      :displayName,
      :cn,
      :puavoSchoolCode,
      :puavoSchoolOID,
      :puavoNamePrefix,
      :puavoSchoolHomePageURL,
      :description,
      :puavoNotes,
      :telephoneNumber,
      :facsimileTelephoneNumber,
      :l,
      :street,
      :postOfficeBox,
      :postalAddress,
      :postalCode,
      :st,
      :puavoLocale,
      :puavoTimezone,
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

    # Deduplicate arrays (LDAP does not like duplicate entries)
    s['puavoTag'] = s['puavoTag'].split.uniq.join(' ') if s.include?('puavoTag')
    s['puavoBillingInfo'].uniq! if s.include?('puavoBillingInfo')
    s['puavoImageSeriesSourceURL'].uniq! if s.include?('puavoImageSeriesSourceURL')

    # Ensure there are no stray whitespaces in these
    s['displayName'].strip! if s.include?('displayName')
    s['cn'].strip! if s.include?('cn')

    clean_image_name(s)
    clear_puavoconf(s)

    s
  end

  # Checks if the current user can edit school WLANs
  def can_edit_wlans?
    return true if is_owner?

    return false unless current_user.has_admin_permission?(:school_edit_wlan)

    return false unless Array(current_user.puavoAdminOfSchool || []).collect { |dn| dn.rdns[0]['puavoId'].to_i }.include?(@school.id.to_i)

    return true
  end
end
