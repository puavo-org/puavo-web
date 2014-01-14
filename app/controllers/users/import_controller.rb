class Users::ImportController < ApplicationController
  require 'prawn/layout'

  class ColumnError < StandardError; end
  class RoleEduPersonAffiliationError < StandardError; end

  Mime::Type.register 'application/pdf', :pdf

  # GET /:school_id/users/import/new
  def new
    respond_to do |format|
      format.html
    end
  end

  # POST /:school_id/users/import/refine
  def refine
    @raw_users = params[:raw_users].split(/[\n\r]+/).map do
      |line| line.split(/[\t,]/)
    end

    @number_of_columns = @raw_users.max {|a,b| a.length <=> b.length}.length

    respond_to do |format|
      format.html # refine.html.erb
    end
  end

  # POST /:school_id/users/import/validate
  # Validate action use following template: refine, role and preview
  def validate
    @raw_users = params[:users]

    if params[:users_import_columns]
      # Verify list of colums (refine.html.erb)

      if params[:users_import_columns].length != params[:users_import_columns].invert.length
        raise ColumnError, t('flash.user.import.dupplicate_column_name_error')
      end

      # Create sort list of columns by params
      # params[:users_import_columns]: {"0" => "givenName", "1" => "sn"}
      # @columns: ["givenName", "sn"]
      @columns = params[:users_import_columns].keys.sort do |a,b|
        a.to_i <=> b.to_i
      end.map do |key|
        params[:users_import_columns][key]
      end

      # givenName and sn is required attributes
      unless @columns.include?('givenName') && @columns.include?('sn')
        raise ColumnError, t('flash.user.import.require_error')
      end
    else
      @columns = params[:columns]
    end

    # Create User object by form data
    @users = User.hash_array_data_to_user( @raw_users,
                                           @columns,
                                           @school )

    # Set puavoEduPersonAffiliation and role to users by params
    if params.has_key?(:user)
      if !@columns.include?("puavoEduPersonAffiliation") &&
          params[:user].has_key?(:puavoEduPersonAffiliation) &&
          !params[:user][:puavoEduPersonAffiliation].empty?
        @columns.push "puavoEduPersonAffiliation"
        puavoEduPersonAffiliation = params[:user][:puavoEduPersonAffiliation]
      end
      if !@columns.include?("role_name") &&
          params[:user].has_key?(:role_name) &&
          !params[:user][:role_name].empty?
        @columns.push "role_name"
        role_name = params[:user][:role_name]
      end
      if !role_name.nil? || !puavoEduPersonAffiliation.nil?
        @users.each do |user|
          unless puavoEduPersonAffiliation.nil?
            user.puavoEduPersonAffiliation = puavoEduPersonAffiliation
          end
          unless role_name.nil?
            user.role_name = Array(role_name)
          end
        end
      end
    end

    # puavoEduPersonAffiliation and role is required attributes
    if !@columns.include?('role_name') || !@columns.include?('puavoEduPersonAffiliation')
      raise RoleEduPersonAffiliationError
    end

    # Validate users
    (@valid_users, @invalid_users) = User.validate_users( @users )

    respond_to do |format|
      format.html do
        @columns.push "uid" unless @columns.include?('uid')
        render 'preview'
      end
    end
  rescue ColumnError => exception
    flash[:notice] = exception.message
    flash[:notice_css_class] = "notice_error"
    @number_of_columns = params[:users_import_columns].length
    @raw_users = to_list(params[:users])
    render "refine"
  rescue RoleEduPersonAffiliationError => exception
    @number_of_columns = @columns.length
    @raw_users = to_list(params[:users])
    @roles = Role.all.delete_if{ |r| r.puavoSchool != @school.dn }
    render "role"
  end

  # POST /:school_id/users/import
  def create

    encrypted_password = Base64.encode64(
      Puavo::RESQUE_WORKER_PUBLIC_KEY.public_encrypt(session[:password_plaintext])
    )

    job_id = UUID.generate
    db = Redis::Namespace.new("puavo:import:#{ job_id }", REDIS_CONNECTION)

    # Save encrypted password separately to redis with expiration date to
    # ensure that it will not persist there for too long
    db.set("pw", encrypted_password)
    db.expire("pw", 60 * 60)
    db.set("status", "waiting")

    Resque.enqueue(
      ImportWorker,
      job_id,
      current_organisation.organisation_key,
      current_user.dn.to_s,
      params
    )

    redirect_to import_status_path(@school, job_id)
  end

  # GET /:school_id/users/import/status/:job_id
  def status

    job_id = params["job_id"]
    db = Redis::Namespace.new("puavo:import:#{ job_id }", REDIS_CONNECTION)
    @import_status = db.get("status")

    if @import_status.nil?
      return render :text => "unknown job", :status => 404
    end

    render :status, :status => :not_found
  end

  # POST /:school_id/users/import/render_pdf/:job_id
  def render_pdf
    job_id = params["job_id"]
    db = Redis::Namespace.new("puavo:import:#{ job_id }", REDIS_CONNECTION)
    pdf_data = db.get("pdf")

    if not pdf_data
      return render :text => "unknown job or not ready", :status => 404
    end

    @import_status = db.del("status")
    @import_status = db.del("pdf")

    send_data(
      pdf_data,
      :type => "application/pdf",
      :filename => "import.pdf",
      :disposition => "attachment"
    )

  end

  # GET /:school_id/users/import/show?create_timestamp=create:20110402152432Z
  def show
    @columns = ["sn", "givenName", "uid", "puavoEduPersonAffiliation", "role_name"]
    @invalid_users = session[:failed_users] ? session[:failed_users][params[:create_timestamp]] : []
    @invalid_users = @invalid_users.map do |attrs|
      u = User.new
      u.attributes = attrs
      u
    end

    @users = User.find( :all,
                        :attribute => "puavoTimestamp",
                        :value => params[:create_timestamp] ) if params[:create_timestamp]
    @users += User.find( :all,
                         :attribute => "puavoTimestamp",
                         :value => params[:change_school_timestamp] ) if params[:change_school_timestamp]

    # Reload roles association
    @users.each do |u| u.roles.reload end

    respond_to do |format|
      format.html
    end
  end

  def user_validate
    @users = params[:users]
    @columns = params[:columns]

    @user = User.new( @users.inject({}) do |result, value|
                        new_value = @columns[value.first.to_i] == params[:column] ? params[:value] : value.last
                        result = result.merge(@columns[value.first.to_i] => new_value)
                      end )

    @user.puavoSchool = @school.dn
    @user.mass_import = true

    User.reserved_uids = params[:uids_list] || []
    @user.valid?

    @user_validation_status = @columns.inject([]) do |result, column|
      status = "true"
      error_message = Array( @user.errors[column] ).first
      unless error_message.nil?
        status = "false"
      end

      index = @columns.index(column)
      result.push( { "index" => index,
                     "value" => params[:column] == column ? params[:value] : @users[index.to_s].first,
                     "status" => status,
                     "error" => error_message } )
    end

    respond_to do |format|
      format.json{ render :json => @user_validation_status }
    end
  end

  def options
    case params[:column]
    when "role_name"
      @data = @school.roles.inject({}){ |result, role| result.merge( {role.displayName => role.displayName } ) }
    when "puavoEduPersonAffiliation"
      @data = User.puavoEduPersonAffiliation_list.inject({}) do |result, type|
        type = I18n.t('puavoEduPersonAffiliation_' + type )
        result.merge({ type => type })
      end
    end


    respond_to do |format|
      format.json { render :json => @data }
    end
  end

  private



  def to_list(data)
    data.keys.sort{ |a,b| a.to_i <=> b.to_i }.map do |key|
      data[key]
    end.transpose
  end
end
