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

    # puavoEduPersonAffiliation and role is required attributes
    if @users.first.role_name.nil?
      if !params.has_key?(:user) ||
          !params[:user].has_key?(:role_name) ||
          params[:user][:role_name].empty?

        raise RoleEduPersonAffiliationError
      end
    end
    if @users.first.puavoEduPersonAffiliation.nil?
      if !params.has_key?(:user) ||
          !params[:user].has_key?(:puavoEduPersonAffiliation) ||
          params[:user][:puavoEduPersonAffiliation].empty?

        raise RoleEduPersonAffiliationError
      end
    end

    @columns.push "puavoEduPersonAffiliation" unless @columns.include?("puavoEduPersonAffiliation")
    @columns.push "role_name" unless @columns.include?("role_name")

    @users.each do |user|
      user.role_name ||= params[:user][:role_name]

      if params[:user] && params[:user][:puavoEduPersonAffiliation]
        user.puavoEduPersonAffiliation = params[:user][:puavoEduPersonAffiliation]
      else
        user.puavoEduPersonAffiliation = User.puavoEduPersonAffiliation_list.select do |value|
          I18n.t( 'puavoEduPersonAffiliation_' + value ).downcase == user.puavoEduPersonAffiliation.downcase
        end
      end
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

    cipher = Gibberish::AES.new(PuavoUsers::Application.config.secret_token)

    encrypted_password = cipher.enc(session[:password_plaintext])

    job_id = UUID.generate
    db = Redis::Namespace.new(
      "puavo:import:#{ job_id }",
      :redis => REDIS_CONNECTION
    )

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

    db = Redis::Namespace.new(
      "puavo:import:#{ job_id }",
      :redis => REDIS_CONNECTION
    )
    @import_status = db.get("status")
    @ttl = db.ttl("status")

    if fail_json = db.get("failed_users")
      @failed_users = Array(JSON.parse(fail_json))
    end

    if @import_status.nil?
      return render_error_page "Unkown import job. You might have downloaded it already."
    end

    render :status, :status => :not_found
  end

  # POST /:school_id/users/import/render_pdf/:job_id
  def render_pdf
    job_id = params["job_id"]
    db = Redis::Namespace.new(
      "puavo:import:#{ job_id }",
      :redis => REDIS_CONNECTION
    )
    encrypted_pdf = db.get("pdf")

    if not encrypted_pdf
      return render_error_page "unknown job or not ready"
    end

    cipher = Gibberish::AES.new(PuavoUsers::Application.config.secret_token)

    pdf_data = cipher.dec(encrypted_pdf)

    duration = 60*5
    if db.ttl("pdf") == -1
      db.expire("status", duration)
      db.expire("pdf", duration)
      db.expire("failed_users", duration)
    end

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
