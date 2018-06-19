class UsersController < ApplicationController

  # GET /:school_id/users
  # GET /:school_id/users.xml
  def index
    if @school
      filter = "(puavoSchool=#{@school.dn})"
    end
    attributes = ['sn', 'givenName', 'uid', 'puavoEduPersonAffiliation', 'puavoId',
                  'puavoSchool',
                  'telephoneNumber',
                  'displayName',
                  'gidNumber',
                  'homeDirectory',
                  'mail',
                  'puavoEduPersonReverseDisplayName',
                  'sambaSID',
                  'uidNumber',
                  'loginShell',
                  'puavoAdminOfSchool',
                  'sambaPrimaryGroupSID',
                  'puavoRemovalRequestTime',
                  'puavoDoNotDelete']

    @users = User.search_as_utf8( :filter => filter,
                          :scope => :one,
                          :attributes => attributes )

    @users = @users.map do |user|
      # ldap values are always arrays. Convert hash values from arrays by
      # grabbing the first value
      Hash[user.last.map { |k,v| [k, v.first] }]
    end.sort do |a,b|
      (a["sn"].to_s + a["givenName"].to_s).downcase <=> (b["sn"].to_s + b["givenName"].to_s).downcase
    end


    if request.format == 'application/json'
      @users = @users.map{ |u| User.build_hash_for_to_json(u) }
    else
      # Split the user list in two halves: one for normal users, one for users who have
      # been marked for deletion. Both arrays are displayed in their own table.
      @users, @users_marked_for_deletion = @users.partition { |u| u["puavoRemovalRequestTime"].nil? }
    end

    respond_to do |format|
      format.html # index.html.erb
      format.xml  { render :xml => @users }
      format.json { render :json => @users }
    end
  end

  # GET /:school_id/users/1/image
  def image
    @user = User.find(params[:id])

    send_data @user.jpegPhoto, :disposition => 'inline', :type => "image/jpeg"
  end

  # GET /:school_id/users/1
  # GET /:school_id/users/1.xml
  def show
    @user = User.find(params[:id])

    # get the creation and modification timestamps from LDAP operational attributes
    extra = User.find(params[:id], :attributes => ['createTimestamp', 'modifyTimestamp'])
    @user['createTimestamp'] = extra['createTimestamp'] || nil
    @user['modifyTimestamp'] = extra['modifyTimestamp'] || nil

    @user_devices = Device.find(:all,
                                :attribute => "puavoDevicePrimaryUser",
                                :value => @user.dn.to_s)

    respond_to do |format|
      format.html # show.html.erb
      format.xml  { render :xml => @user }
      # FIXME, remove user key?
      format.json  { render :json => @user  }
    end
  end

  # GET /:school_id/users/new
  # GET /:school_id/users/new.xml
  def new
    @user = User.new
    @groups = @school.groups
    @roles = @school.roles
    @user_roles =  []

    @edu_person_affiliation = @user.puavoEduPersonAffiliation || []

    respond_to do |format|
      # FIXME: whether the student management system is in use?
      if users_synch?(@school) && !current_user.organisation_owner?
        flash[:alert] = t('flash.user.cannot_create_user')
        format.html { redirect_to( users_url ) }
      else
        format.html # new.html.erb
      end
      format.xml  { render :xml => @user }
    end
  end

  # GET /:school_id/users/1/edit
  def edit
    @user = User.find(params[:id])
    @groups = @school.groups
    @roles = @school.roles
    @user_roles =  @user.roles || []

    @edu_person_affiliation = @user.puavoEduPersonAffiliation || []

    get_user_groups
  end

  # POST /:school_id/users
  # POST /:school_id/users.xml
  def create
    @user = User.new(user_params)
    @groups = @school.groups
    @roles = @school.roles
    @user_roles =  []

    # TODO: should we use the filtered hash returned by "user_params" here
    # instead of modifying the raw unfiltered "params" object?
    params[:user][:puavoEduPersonAffiliation] ||= []
    @edu_person_affiliation = params[:user][:puavoEduPersonAffiliation]

    @user.puavoSchool = @school.dn

    respond_to do |format|
      begin
        unless @user.save
          raise User::UserError, I18n.t('flash.user.create_failed')
        end
        if new_group_management?(@school)
          format.html { redirect_to( group_user_path(@school,@user) ) }
          format.json { render :json => nil }
        else
          flash[:notice] = t('flash.added', :item => t('activeldap.models.user'))
          format.html { redirect_to( user_path(@school,@user) ) }
          format.json { render :json => nil }
        end
      rescue User::UserError => e
        logger.info "Create user, Exception: " + e.to_s
        @user_roles = params[:user][:role_ids].nil? ? [] : Role.find(params[:user][:role_ids]) || []
        error_message_and_render(format, 'new', e.message)
      end
    end
  end

  # PUT /:school_id/users/1
  # PUT /:school_id/users/1.xml
  def update
    @user = User.find(params[:id])
    @groups = @school.groups
    @roles = @school.roles
    @user_roles =  @user.roles || []

    params[:user][:puavoEduPersonAffiliation] ||= []
    @edu_person_affiliation = params[:user][:puavoEduPersonAffiliation]

    if @user.read_only?
      params["user"].delete(:givenName)
      params["user"].delete(:sn)
      params["user"].delete(:uid)
      params["user"].delete(:mail)
      params["user"].delete(:telephoneNumber)
      params["user"].delete(:role_ids)
      params["user"].delete(:puavoLocale)
    end

    respond_to do |format|
      begin
        unless @user.update_attributes(user_params)
          raise User::UserError, I18n.t('flash.user.save_failed')
        end

        if new_group_management?(@school)
          if params["teaching_group"]
            @user.teaching_group = params["teaching_group"]
          end
          if params["administrative_groups"]
            @user.administrative_groups = params["administrative_groups"].delete_if{ |id| id == "0" }
            params["user"].delete("administrative_groups")
          end
        end

        # Save new password to session otherwise next request does not work
        if session[:dn] == @user.dn
          unless params[:user][:new_password].nil? || params[:user][:new_password].empty?
            session[:password_plaintext] = params[:user][:new_password]
          end
        end
        flash[:notice] = t('flash.updated', :item => t('activeldap.models.user'))
        format.html { redirect_to( user_path(@school,@user) ) }
      rescue User::UserError => e
        @user_roles = params[:user][:role_ids].nil? ? [] : Role.find(params[:user][:role_ids]) || []
        get_user_groups
        error_message_and_render(format, 'edit',  e.message)
      end
    end
  end

  # DELETE /:school_id/users/1
  # DELETE /:school_id/users/1.xml
  def destroy
    @user = User.find(params[:id])

    if @user.puavoDoNotDelete
      flash[:alert] = t('flash.user_deletion_prevented')
    else
      if @user.puavoEduPersonAffiliation == 'admin'
        # if an admin user is also an organisation owner, remove the ownership
        # automatically before deletion
        owners = LdapOrganisation.current.owner.each.select { |dn| dn != "uid=admin,o=puavo" }

        if !owners.nil? && owners.include?(@user.dn)
          if !LdapOrganisation.current.remove_owner(@user)
            flash[:alert] = t('flash.organisation_ownership_not_removed')
          else
            # TODO: Show a flash message when ownership is removed. First we need to
            # support multiple flash messages of the same type...
            #flash[:notice] = t('flash.organisation_ownership_removed')
          end
        end
      end

      if @user.destroy
        flash[:notice] = t('flash.destroyed', :item => t('activeldap.models.user'))
      end
    end

    respond_to do |format|
      format.html { redirect_to(users_url) }
      format.xml  { head :ok }
    end
  end

  # POST /:school_id/users/change_school
  def change_school
    @new_school = School.find(params[:new_school])

    use_groups = new_group_management?(@school)
    @role_or_group = use_groups ? Group.find(params[:new_role]) : Role.find(params[:new_role])

    params[:user_ids].each do |user_id|
      @user = User.find(user_id)
      @user.change_school(@new_school.dn.to_s)

      if use_groups
        @user.groups = Array(@role_or_group.id)
      else
        @user.role_ids = Array(@role_or_group.id)
      end

      @user.save
    end

    respond_to do |format|
      if Array(params[:user_ids]).length > 1
        format.html { redirect_to( role_path( @new_school,
                                              @role_or_group ),
                                   :notice => t("flash.user.school_changed") ) }
      else
        format.html { redirect_to( user_path(@new_school, @user),
                                   :notice => t("flash.user.school_changed") ) }
      end
    end
  end

  # GET /:school_id/users/:id/select_school
  def select_school
    @user = User.find(params[:id])
    @schools = School.all_with_permissions current_user

    # don't show the school the user already is in
    user_school_id = @user.puavoSchool&.rdns[0]["puavoId"] || -1
    @schools.reject! { |s| s.id == user_school_id }

    respond_to do |format|
      format.html
    end
  end

  # POST /:school_id/users/:id/select_role
  def select_role
    @user = User.find(params[:id])
    @new_school = School.find(params[:new_school])

    @use_groups = new_group_management?(@school)
    @roles_or_groups = @use_groups ? @new_school.groups : @new_school.roles
    @is_a_student = false

    if @use_groups
      # only show certain kinds of groups, based on the user's type
      if @user.puavoEduPersonAffiliation == 'student'
        # display only teaching groups for students
        @roles_or_groups.select! { |g| g.puavoEduGroupType == 'teaching group' }
        is_a_student = true
      else
        # for everyone else, teachers or not, display only administrative groups
        @roles_or_groups.select! { |g| g.puavoEduGroupType == 'administrative group' }
      end
    end

    if @roles_or_groups.nil? || @roles_or_groups.empty?
      if is_a_student
        # special message for students
        flash[:alert] = t('users.select_school.no_teaching_groups')
      else
        if @use_groups
          flash[:alert] = t('users.select_school.no_groups')
        else
          flash[:alert] = t('users.select_school.no_roles')
        end
      end

      redirect_to :back
    else
      respond_to do |format|
        format.html
      end
    end
  end

  # GET /users/:school_id/users/:id/group
  def group
    @user = User.find(params[:id])

    get_user_groups

    respond_to do |format|
      format.html
    end
  end

  # PUT /users/:school_id/users/:id/group
  def add_group
    @user = User.find(params[:id])

    if params["administrative_groups"]
      @user.administrative_groups = params["administrative_groups"].delete_if{ |id| id == 0 }
    end
    @user.teaching_group = params["teaching_group"]

    respond_to do |format|
      format.html { redirect_to( user_path(@school, @user) ) }
    end
  end

  def username_redirect
    user = User.find(:first, :attribute => "uid", :value => params["username"])
    if user.nil?
      return render :plain => "Unknown user #{ ActionController::Base.helpers.sanitize(params["username"]) }", :status => 400
    end
    redirect_to user_path(params["school_id"], user.id)
  end

  def mark_for_deletion
    @user = User.find(params[:id])

    if @user.puavoRemovalRequestTime.nil?
      @user.puavoRemovalRequestTime = Time.now.utc
      @user.save
      flash[:notice] = t('flash.user.marked_for_deletion')
    else
      flash[:alert] = t('flash.user.already_marked_for_deletion')
    end

    respond_to do |format|
      format.html { redirect_to( user_path(@school, @user) ) }
    end
  end

  def unmark_for_deletion
    @user = User.find(params[:id])

    if @user.puavoRemovalRequestTime
      @user.puavoRemovalRequestTime = nil
      @user.save
      flash[:notice] = t('flash.user.unmarked_for_deletion')
    else
      flash[:alert] = t('flash.user.not_marked_for_deletion')
    end

    respond_to do |format|
      format.html { redirect_to( user_path(@school, @user) ) }
    end
  end

  private

  def error_message_and_render(format, action, message = nil)
    flash[:alert] = message unless message.nil?

    format.html { render :action => action }
    format.xml  { render :xml => @user.errors, :status => :unprocessable_entity }
  end

  def get_user_groups
    @teaching_groups = rest_proxy.get("/v3/schools/#{ @school.puavoId }/teaching_groups").parse
    administrative_groups = rest_proxy.get("/v3/administrative_groups").parse or []

    @administrative_groups_by_school = {}
    administrative_groups.each do |g|
      unless @administrative_groups_by_school[g["school_id"]]
        @administrative_groups_by_school[g["school_id"]] = {}
        @administrative_groups_by_school[g["school_id"]]["school_name"] = School.find(g["school_id"]).displayName
      @administrative_groups_by_school[g["school_id"]]["groups"] = []
      end
      @administrative_groups_by_school[g["school_id"]]["groups"].push g
    end

  end

  private
    def user_params
      u = params.require(:user).permit(
          :givenName,
          :sn,
          :uid,
          :puavoLocale,
          :puavoAllowRemoteAccess,
          :puavoEduPersonPersonnelNumber,
          :image,
          :puavoLocked,
          :puavoSshPublicKey,
          :puavoExternalId,
          :new_password,
          :new_password_confirmation,
          :mail=>[],
          :telephoneNumber=>[],
          :puavoEduPersonAffiliation=>[],
          :role_ids=>[]).to_hash

      # deduplicate arrays, as LDAP really does not like duplicate entries...
      u["mail"].uniq! if u.key?("mail")
      u["telephoneNumber"].uniq! if u.key?("telephoneNumber")

      return u

    end

end
