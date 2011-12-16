class UsersController < ApplicationController
  before_filter :find_roles, :only => [:new, :edit, :create, :update]

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

    @users = User.base_search( :filter => filter,
                               :scope => :one,
                               :attributes => attributes )
    
    @users = @users.sort do |a,b|
      a["sn"].to_s + a["givenName"].to_s <=> b["sn"].to_s + b["givenName"].to_s
    end

    @roles_by_user_dn =
      SchoolRole.base_search( :filter => "puavoSchool=#{@school.dn}",
                              :attributes => ['member',
                                              'displayName'] ).inject({}) do |result, role|
      Array(role[:member]).each do |member|
        result[member.to_s] = Array(result[member].to_s) + [ role[:displayName] ]
      end
      result
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

    # Convert array to hash
    # Example: {"cn" => "Pavel Taylor","givenName" => "Pavel","gidNumber":=> "10567"
    json_user = @user.inject({}) do |result, array|
      result[array[0]] = array[1].to_s
      result
    end

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
    @student_classes = StudentYearClass.classes_by_school(@school)
    @user = User.new

    respond_to do |format|
      format.html # new.html.erb
      format.xml  { render :xml => @user }
    end
  end

  # GET /:school_id/users/1/edit
  def edit
    @user = User.find(params[:id])
    @user.role_ids = @user.roles.map{ |r| r.puavoId.to_s }
    @student_classes = StudentYearClass.classes_by_school(@school)
  end

  # POST /:school_id/users
  # POST /:school_id/users.xml
  def create
    @student_classes = StudentYearClass.classes_by_school(@school)
    @user = User.new(params[:user])

    @user.puavoSchool = @school.dn

    respond_to do |format|
      begin
        unless @user.save
          raise
        end
        flash[:notice] = t('flash.added', :item => t('activeldap.models.user'))
        format.html { redirect_to( user_path(@school,@user) ) }
      rescue User::PasswordChangeFailed => e
        flash[:alert] = t('flash.password_set_failed')
        format.html { redirect_to( user_path(@school,@user) ) }
      #rescue ActiveLdap::LdapError::ConstraintViolation
      rescue Exception => e
        logger.info "Create user, Exception: " + e.to_s
        error_message_and_render(format, 'new', t('flash.user.create_failed'))
      end
    end
  end

  # PUT /:school_id/users/1
  # PUT /:school_id/users/1.xml
  def update
    @student_classes = StudentYearClass.classes_by_school(@school)
    @user = User.find(params[:id])

    respond_to do |format|
      begin
        unless @user.update_attributes(params[:user])
          raise
        end
        # Save new password to session otherwise next request does not work
        if session[:dn] == @user.dn
          unless params[:user][:new_password].nil? || params[:user][:new_password].empty?
            session[:password_plaintext] = params[:user][:new_password]
          end
        end
        flash[:notice] = t('flash.updated', :item => t('activeldap.models.user'))
        format.html { redirect_to( user_path(@school,@user) ) }
      rescue User::PasswordChangeFailed => e
        error_message_and_render(format, 'edit',  t('flash.password_set_failed'))
      rescue Exception => e
        logger.info "Update user, Exception: " + e.to_s
        error_message_and_render(format, 'edit', t('flash.user.save_failed'))
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

    params[:user_ids].each do |user_id|
      @user = User.find(user_id)
      user_old_school_roles = SchoolRole.find( :all,
                                               :attribute => "member",
                                               :value => @user.dn.to_s )
      user_new_school_roles = SchoolRole.find( :all,
                                               :attribute => "puavoSchool",
                                               :value => @new_school.dn.to_s ).select do |role|
        user_old_school_roles.map{ |ur| ur.puavoRole }.include?(role.puavoRole)
      end
      @user.change_school(@new_school.dn.to_s)
      @user.student_class_id = params[:new_student_class]
      @user.role_ids = user_new_school_roles.map{ |r| r.puavoId.to_s }
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
    @schools = School.all_with_permissions

    respond_to do |format|
      format.html
    end
  end

  # POST /:school_id/users/:id/select_student_class
  def select_student_class
    @user = User.find(params[:id])
    @new_school = School.find(params[:new_school])
    @student_classes = StudentYearClass.classes_by_school(@new_school)

    respond_to do |format|
      format.html
    end
  end

  private

  def error_message_and_render(format, action, message = nil)
    flash[:alert] = message unless message.nil?

    format.html { render :action => action }
    format.xml  { render :xml => @user.errors, :status => :unprocessable_entity }
  end

  def find_roles
    @roles = SchoolRole.find( :all,
                              :attribute => "puavoSchool",
                              :value => @school.dn.to_s )
  end
end
