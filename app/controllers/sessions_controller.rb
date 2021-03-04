class SessionsController < ApplicationController
  include Puavo::LoginCustomisations

  layout 'sessions'

  skip_before_action :require_puavo_authorization, :only => [ :new, :create ]

  skip_before_action :require_login, :only => [ :new, :create ]

  def new
    # Base content
    @login_content = {
      # "prefix" must be set, because the same form is used for puavo-web and
      # puavo-rest, but their contents (CSS, etc.) are stored in different
      # places. This key tells the form where those resources are.
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

    # Per-customer customisations, if any
    @login_content.merge!(customise_login_screen())

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

    # Forget language changes
    session.delete :user_locale

    redirect_to login_path
  end

  # Temporarily override the language defined in organisations.yml. The override
  # lasts until logout.
  def change_language
    unless params.include?(:lang) && Rails.configuration.available_ui_locales.include?(params[:lang])
      flash[:alert] = t('flash.session.invalid_language')
    else
      # If the new language is the organisation default, remove the custom key
      if params[:lang] == current_organisation.locale
        session.delete :user_locale
      else
        session[:user_locale] = params[:lang]
      end
    end

    redirect_back(fallback_location: "/users")
  end
end
