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
                  'sambaPrimaryGroupSID']

    @users = User.search_as_utf8( :filter => filter,
                          :scope => :one,
                          :attributes => attributes )

    @users = @users.map do |user|
      # ldap values are always arrays. Convert hash values from arrays by
      # grabbing the first value
      Hash[user.last.map { |k,v| [k, v.first] }]
    end.sort do |a,b|
      a["sn"].to_s + a["givenName"].to_s <=> b["sn"].to_s + b["givenName"].to_s
    end


    if request.format == 'application/json'
      @users = @users.map{ |u| User.build_hash_for_to_json(u) }
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
      if new_group_management?(@school) && !current_user.organisation_owner?
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
    @user = User.new(params[:user])
    @groups = @school.groups
    @roles = @school.roles
    @user_roles =  []

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
        else
          flash[:notice] = t('flash.added', :item => t('activeldap.models.user'))
          format.html { redirect_to( user_path(@school,@user) ) }
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
        unless @user.update_attributes(params[:user])
          raise User::UserError, I18n.t('flash.user.save_failed')
        end

        @user.teaching_group = params["teaching_group"]
        if params["administrative_groups"]
          @user.administrative_groups = params["administrative_groups"].delete_if{ |id| id == "0" }
          params["user"].delete("administrative_groups")
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
        error_message_and_render(format, 'edit',  e.message)
      end
    end
  end

  # DELETE /:school_id/users/1
  # DELETE /:school_id/users/1.xml
  def destroy
    @user = User.find(params[:id])
    if @user.destroy
      flash[:notice] = t('flash.destroyed', :item => t('activeldap.models.user'))
    end

    respond_to do |format|
      format.html { redirect_to(users_url) }
      format.xml  { head :ok }
    end
  end

  # POST /:school_id/users/change_school
  def change_school
    @new_school = School.find(params[:new_school])
    @new_role = Role.find(params[:new_role])

    params[:user_ids].each do |user_id|
      @user = User.find(user_id)
      @user.change_school(@new_school.dn.to_s)
      @user.role_ids = Array(@new_role.id)
      @user.save
    end

    respond_to do |format|
      if Array(params[:user_ids]).length > 1
        format.html { redirect_to( role_path( @new_school,
                                              @new_role ),
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

    respond_to do |format|
      format.html
    end
  end

  # POST /:school_id/users/:id/select_role
  def select_role
    @user = User.find(params[:id])
    @new_school = School.find(params[:new_school])
    @roles = @new_school.roles

    respond_to do |format|
      format.html
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
      return render :text => "Unknown user #{ params["username"] }", :status => 400
    end
    redirect_to user_path(params["school_id"], user.id)
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
end
