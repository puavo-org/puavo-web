class SessionsController < ApplicationController
  layout 'sessions'

  skip_before_action :require_puavo_authorization, :only => [ :new, :create ]

  skip_before_action :require_login, :only => [ :new, :create ]

  def new
    begin
      # Any per-organisation login screen customisations?
      org_key = organisation_key_from_host

      logger.info("Organisation key: \"#{org_key}\"")

      customisations = Puavo::Organisation
        .find(org_key)
        .value_by_key('login_screen')

      customisations = {} unless customisations.class == Hash
    rescue StandardError => e
      customisations = {}
    end

    unless customisations.empty?
      logger.info("This organisation has login screen customisations enabled")
    end

    # Base content
    @login_content = {
      "prefix" => "/login",
      "external_service_name" => I18n.t("sessions.new.external_service_name"),
      "service_title_override" => nil,
      "return_to" => params['return_to'] || params['return'] || nil,
      "organisation" => request.host,
      "display_domain" => request.host,   # used mainly in SSO code, but must be set here too
      "username_placeholder" => I18n.t("sessions.new.username_placeholder"),
      "username" => params["username"],
      "error_message" => flash[:notice],
      "topdomain" => PUAVO_ETC.topdomain,
      "text_password" => I18n.t("sessions.new.password"),
      "text_login" => I18n.t("sessions.new.login"),
      "text_help" => I18n.t("sessions.new.help"),
      "text_username_help" => I18n.t("sessions.new.username_help"),
      "text_organisation_help" => I18n.t("sessions.new.organisation_help"),
      "text_developers" => I18n.t("sessions.new.developers"),
      "text_developers_info" => I18n.t("sessions.new.developers_info"),
      "text_login_to" => I18n.t("sessions.new.login_to")
    }

    # Apply per-customer customisations
    if customisations.include?('css')
      @login_content['css'] = customisations['css']
    end

    if customisations.include?('upper_logo')
      @login_content['upper_logo'] = customisations['upper_logo']
    end

    if customisations.include?('header_text')
      @login_content['header_text'] = customisations['header_text']
    end

    if customisations.include?('service_title_override')
      @login_content['service_title_override'] = customisations['service_title_override']
    end

    if customisations.include?('bottom_logos')
      @login_content['bottom_logos'] = customisations['bottom_logos']
    end

    respond_to do |format|
      format.html do
        render :file => "rest/views/login_form"
      end
    end

  end

  def create
    session[:uid] = params[:username]
    session[:password_plaintext] = params[:password]
    redirect_back_or_default  rack_mount_point
  end

  def auth
    respond_to do |format|
      format.json { render :json => true.to_json }
    end
  end

  def show
    @user = current_user
    respond_to do |format|
      format.json  { render :json => @user.as_json(:methods => :managed_schools) }
    end
  end

  def destroy
    # Remove dn and plaintext password values from session
    session.delete :password_plaintext
    session.delete :uid
    redirect_to login_path
  end
end
