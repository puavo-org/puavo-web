module UsersHelper
  def profile_image_path(user=nil)
    user ||= current_user
    if user.jpegPhoto
      image_user_path(user.school.id, user.id)
    else
      "anonymous.png"
    end
  end
end
