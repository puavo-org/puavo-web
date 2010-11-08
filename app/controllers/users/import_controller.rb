class Users::ImportController < ApplicationController
  require 'prawn/layout'

  class OnlyRawData < StandardError; end
  class ColumnError < StandardError; end

  Mime::Type.register 'application/pdf', :pdf

  # GET /:school_id/users/import/new
  def new
    session[:taken_uids_by_puavoId] = Hash.new
    respond_to do |format|
      format.html
    end
  end

  # GET /:school_id/users/import/refine
  def refine
    User.taken_uids_by_puavoId = session[:taken_uids_by_puavoId]
    @invalid_users = []
    @columns =  session[:users_import_columns] if session.has_key?(:users_import_columns)

    if session.has_key?(:users_import_instance_list) && session[:users_import_instance_list].has_key?(:invalid)
      @invalid_users = session[:users_import_instance_list][:invalid]
    elsif session.has_key?(:users_import_raw_list)
      @raw_users = session[:users_import_raw_list]
    end

    # Add attribute to list of displayed fields if attribute value is invalid
    @invalid_users.each do |user|
      user.errors.each do |column, message|
        @columns.push column unless @columns.include?(column)
      end
    end

    respond_to do |format|
      format.html
    end
  end
  
  # GET /:school_id/users/import/validate
  # POST /:school_id/users/import/validate
  def validate
    User.taken_uids_by_puavoId = session[:taken_uids_by_puavoId]
    @columns = []
    
    if params.has_key?(:users_import_raw_list)
      session[:users_import_raw_list] = params[:users_import_raw_list].values.transpose
    end

    if params.has_key?(:users_csv_list)
      # Convert data to array.
      session[:users_import_raw_list] = params[:users_csv_list].split(/[\n\r]+/).map do
        |line| line.split("\t")
      end
      # Clean older value
      session[:users_import_columns] = nil
      session[:users_import_instance_list] = nil
      raise OnlyRawData
    end
    if params.has_key?(:users_import_columns)
      # Set column name into @columns array order by column location on table
      # params[:user][:column]: {"0" => "Surname", "1" => "Given name", "2" => "Role" }
      # @columns: ["Surname", "Given name", "Role"]
      @columns =  params[:users_import_columns].keys.sort do |a,b|
        a.to_i <=> b.to_i 
      end.map do |key|
        params[:users_import_columns][key]
      end
      session[:users_import_columns] = @columns
      if params[:users_import_columns].length != params[:users_import_columns].invert.length
        raise ColumnError, t('flash.user.import.dupplicate_column_name_error')
      end
    else
      @columns =  session[:users_import_columns] if session.has_key?(:users_import_columns)
    end 

    unless @columns.include?('givenName') && @columns.include?('sn')
      raise ColumnError, t('flash.user.import.require_error')
    end

    if params.has_key?(:users_import_raw_list)
      session[:users_import_instance_list] =
        User.validate_users( User.hash_array_data_to_user( params[:users_import_raw_list],
                                                                   @columns,
                                                                   @school ) )
    elsif params.has_key?(:users_import_invalid_list)
      users_import_invalid_list =
        User.validate_users( User.hash_array_data_to_user( params[:users_import_invalid_list],
                                                                   @columns,
                                                                   @school ) )
      session[:users_import_instance_list][:valid] += users_import_invalid_list[:valid]
      session[:users_import_instance_list][:invalid] = users_import_invalid_list[:invalid]
    elsif session.has_key?(:users_import_instance_list)
      session[:users_import_instance_list] =
        User.validate_users( session[:users_import_instance_list][:valid] +
                                 session[:users_import_instance_list][:invalid] )
    end

    session[:taken_uids_by_puavoId] = User.taken_uids_by_puavoId

    respond_to do |format|
      format.html do
        if @columns.include?('role_ids') && 
            !session[:users_import_instance_list][:invalid].empty? &&
            session[:users_import_instance_list][:invalid].first.errors.on("role_ids")
          flash[:notice] = t('flash.user.import.role_require_error')
          redirect_to role_users_import_path(@school)
        elsif ( !@columns.include?('role_name') && !@columns.include?('role_ids') ) ||
            ( !@columns.include?('puavoEduPersonAffiliation') )
          redirect_to role_users_import_path(@school) 
        elsif session[:users_import_instance_list][:invalid].empty?
          redirect_to preview_users_import_path(@school)
        else
          redirect_to refine_users_import_path(@school)
        end
      end
    end
  rescue OnlyRawData => exception
    redirect_to refine_users_import_path(@school)
  rescue ColumnError => exception
    flash[:notice] = exception.message
    flash[:notice_css_class] = "notice_error"
    redirect_to refine_users_import_path(@school)
  end
  
  # GET /:school_id/users/import/role
  # PUT /:school_id/users/import/role
  def role
    @columns = session[:users_import_columns]

    if params.has_key?(:user)
      if params[:user].has_key?(:puavoEduPersonAffiliation) && !@columns.include?("puavoEduPersonAffiliation")
        @columns.push "puavoEduPersonAffiliation"
      end
      if params[:user].has_key?(:role_ids) && !@columns.include?("role_ids")
        @columns.push "role_ids"
      end
      session[:users_import_instance_list].each_value do |users|
        users.each do |user|
          if params[:user].has_key?(:puavoEduPersonAffiliation)
            user.puavoEduPersonAffiliation = params[:user][:puavoEduPersonAffiliation]
          end
          if params[:user].has_key?(:role_ids)
            user.role_ids = Array(params[:user][:role_ids])
          end
        end
      end
    end
    
    respond_to do |format|
      format.html do
        if request.method == :put
          redirect_to validate_users_import_path(@school)
        end
      end
    end
  end

  # GET /:school_id/users/import/preview
  def preview
    @valid_users = session[:users_import_instance_list][:valid]
    @columns = session[:users_import_columns]
    @columns.push "uid" unless @columns.include?('uid')
  end

  # POST /:school_id/users/import
  def create
    @users = session[:users_import_instance_list][:valid]

    users_of_roles = Hash.new

    @users.each do |user|
      if user.new_password.nil? or user.new_password.empty?
        user.generate_password
      end
      role_id = Array(user.role_ids).first.to_s
      users_of_roles[role_id] = Array.new unless users_of_roles.has_key?(role_id)
      users_of_roles[role_id].push user
      user.save
    end

    users_of_school = User.find(:all, :attribute => 'puavoSchool', :value => @school.dn )
    @school.memberUid = users_of_school.map &:uid
    @school.member = users_of_school.map &:dn
    @school.save

    SambaGroup.add_uid_to_memberUid( 'Domain Users', (@users.map &:uid) )

    users_of_roles.each do |role_id, values|
      role = Role.find(role_id)
      role.member = Array(role.member) + (values.map &:dn)
      role.memberUid = Array(role.memberUid) + (values.map &:uid)
      role.save
      role.update_associations
    end

    respond_to do |format|
      format.html { redirect_to users_import_path(@school) }
    end
  end

  # GET /:school_id/users/import/show
  def show
    @users = session[:users_import_instance_list][:valid]

    # Reload roles association
    @users.each do |u| u.roles.reload end

    respond_to do |format|
      format.html
      format.pdf do
        send_data(
                  create_pdf(@users),
                  :filename => 'users_list.pdf',
                  :type => 'application/pdf',
                  :disposition => 'inline' )
      end
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
        pdf.text "#{t('activeldap.attributes.user.password')}: #{user.new_password}\n\n\n"
        users_of_page_count += 1
        if users_of_page_count > 10 && user != users.last
          users_of_page_count = 0
          pdf.start_new_page
        end
      end
      pdf.repeat start_page_number..pdf.page_number do
        pdf.draw_text "#{session[:organisation].name}, #{@school.displayName}, #{users.first.roles.first.displayName}", :at => pdf.bounds.top_left
      end
    end
  end
end
