class ThemesController < ActionController::Base

  layout :false

  def set_theme

    session[:theme] = params[:theme]

    render :update do |page|
      page.reload
    end
  end
end
