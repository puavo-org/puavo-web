class SessionsController < ApplicationController
  layout 'sessions'
  skip_before_filter :require_puavo_authorization, :only => [ :new,
                                                              :create,
                                                              :logo,
                                                              :login_helpers,
                                                              :theme ]
  skip_before_filter :require_login, :only => [ :new,
                                                :create,
                                                :logo,
                                                :login_helpers,
                                                :theme ]

  def new

    @login_content = {
      "opinsys_logo_url" => "logo.png",
      "external_service_name" =>  I18n.t("sessions.new.external_service_name"),
      "return_to" => params["return_to"],
      "organisation" => {
        "name" => request.host, # FIXME
        "domain" => request.host
      },
      "username_placeholder" => I18n.t("sessions.new.username_placeholder"),
      "username" => params["username"],
      "invalid_credentials?" => false, # Not use plaintext password ever
      "handheld?" => true, # Not use plaintext password ever
      "error_message" => flash[:notice],
      "topdomain" => PUAVO_ETC.topdomain,
      "login_helper_js_url" => "login/helpers.js",
      "text_password" => I18n.t("sessions.new.password"),
      "text_login" => I18n.t("sessions.new.login"),
      "text_help" => I18n.t("sessions.new.help"),
      "text_username_help" => I18n.t("sessions.new.username_help"),
      "text_organisation_help" => I18n.t("sessions.new.organisation_help"),
      "text_developers" => I18n.t("sessions.new.developers"),
      "text_developers_info" => I18n.t("sessions.new.developers_info"),
      "text_login_to" => I18n.t("sessions.new.login_to")
    }

    respond_to do |format|
      format.html do
        render :file => "rest/views/login_form"
      end
    end

  end

  def logo
    send_file( Rails.root.join('rest', 'public', 'v3', 'img', 'opinsys_logo.png'),
               :type => 'image/png',
               :disposition => 'inline' )
  end

  def login_helpers
     send_file( Rails.root.join('rest', 'public', 'v3', 'scripts', 'login_helpers.js'),
               :type => 'application/javascript',
               :disposition => 'inline' )

  end

  def theme
    send_file( Rails.root.join('rest', 'public', 'v3', 'styles', 'theme.css'),
               :type => 'text/css',
               :disposition => 'inline' )
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
