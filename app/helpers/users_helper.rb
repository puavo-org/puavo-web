module UsersHelper
  include Puavo::Helpers

  def default_image_or_user_image_path(path, user)
    if user.jpegPhoto
      path
    else
      "anonymous.png"
    end
  end
end
