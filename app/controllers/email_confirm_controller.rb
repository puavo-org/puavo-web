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
    # jwt
    # password


    respond_to do |format|
      format.html { redirect_to( successfully_email_confirm_path ) }
    end
  end

  def successfully

    respond_to do |format|
      format.html
    end
  end

end
