module UsersHelper
  def profile_image_path(user=nil)
    user ||= current_user
    if user.jpegPhoto
      image_profile_path
    else
      "anonymous.png"
    end
  end
end
