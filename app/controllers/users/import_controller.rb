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

    # Save encrypted password separately to redis with expiration date to
    # ensure that it will not persist there for too long
    Puavo::REDIS.set("import:#{ job_id }:pw", encrypted_password)
    Puavo::REDIS.expire("import:#{ job_id }:pw", 60 * 60)
    Puavo::REDIS.set("import:#{ job_id }:status", "waiting")

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
    render :text => Puavo::REDIS.get("import:#{ job_id }:status")
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

  # POST /:school_id/users/import/generate_passwords_pdf?create_timestamp=create:20110402152432Z
  def generate_passwords_pdf
    password_timestamp = "password:#{current_user.dn}:" + Time.now.getutc.strftime("%Y%m%d%H%M%SZ")

    @users = User.find( :all,
                        :attribute => "puavoTimestamp",
                        :value => params[:create_timestamp] ) if params[:create_timestamp]

    @users.each do |user|
      user.set_generated_password if params[:reset_password] == "true"
      # Update puavoTimestamp
      user.puavoTimestamp = Array(user.puavoTimestamp).push password_timestamp
      user.save!
    end

    if params[:change_school_timestamp]
      User.find( :all,
                 :attribute => "puavoTimestamp",
                 :value => params[:change_school_timestamp] ).each do |user|
        user.earlier_user = true
        @users.push user
      end
    end

    # Reload roles association
    @users.each do |u| u.roles.reload end

    filename = current_organisation.organisation_key + "_" +
      @school.cn + "_" + Time.now.strftime("%Y%m%d") + ".pdf"

    respond_to do |format|
      format.pdf do
        send_data(
                  create_pdf(@users),
                  :filename => filename,
                  :type => 'application/pdf',
                  :disposition => 'attachment' )
      end
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

  def create_pdf(users)
    role_name = String.new
    pdf = Prawn::Document.new( :skip_page_creation => true, :page_size => 'A4')

    users_by_role = User.list_by_role(users)
    users_by_role.each do |users|
      role_to_pdf(users, pdf)
    end
    pdf.render
  end

  def role_to_pdf(users, pdf)
    pdf.start_new_page
    pdf.font "Times-Roman"
    pdf.font_size = 12
    start_page_number = pdf.page_number

    # Sort users by sn + givenName
    users = users.sort{|a,b| a.sn + a.givenName <=> b.sn + a.givenName }

    pdf.text "\n"

    users_of_page_count = 0
    users.each do |user|
      pdf.indent(300) do
        pdf.text "#{t('activeldap.attributes.user.displayName')}: #{user.displayName}"
        pdf.text "#{t('activeldap.attributes.user.uid')}: #{user.uid}"
        if user.earlier_user
          pdf.text t('controllers.import.school_has_changed') + "\n\n\n"
        else
          pdf.text "#{t('activeldap.attributes.user.password')}: #{user.new_password}\n\n\n"
        end
        users_of_page_count += 1
        if users_of_page_count > 10 && user != users.last
          users_of_page_count = 0
          pdf.start_new_page
        end
      end
      pdf.repeat start_page_number..pdf.page_number do
        pdf.draw_text "#{current_organisation.name}, #{@school.displayName}, #{users.first.roles.first.displayName}", :at => pdf.bounds.top_left
      end
    end
  end

  def to_list(data)
    data.keys.sort{ |a,b| a.to_i <=> b.to_i }.map do |key|
      data[key]
    end.transpose
  end
end
