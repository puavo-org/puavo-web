class EmailConfirmController < ApplicationController
  skip_before_filter  :find_school, :require_login, :require_puavo_authorization
  layout "password"

  # GET /users/email_confirm/:jwt
  def preview
    # validate jwt

    respond_to do |format|
      format.html
    end
  end

  # PUT /users/email_confirm
  def confirm
    begin

      jwt_data = JWT.decode(params[:jwt], Puavo::CONFIG["email_confirm_secret"])

      perform_login( :uid => jwt_data["username"],
                     :organisation_key => organisation_key_from_host(jwt_data["organisation_domain"]),
                     :password => params[:email_confirm][:password] )

      User.ldap_modify_operation( current_user.dn,
                                  :add, [{ "mail" => [jwt_data["email"]] }] )

      respond_to do |format|
        format.html { redirect_to( successfully_email_confirm_path ) }
      end

    rescue Puavo::AuthenticationFailed
      # invalid password, redirect?
      # FIXME redirect to the main page. Show "Invalid password" message
      render :error
    rescue ActiveLdap::LdapError::TypeOrValueExists
      # email address already exists
      render :error
    rescue JWT::DecodeError
      # invalid jwt token
      render :error
    end
  end

  def successfully

    respond_to do |format|
      format.html
    end
  end

end
