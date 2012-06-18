module NavigationHelpers
  # Maps a name to a path. Used by the
  #
  #   When /^I go to (.+)$/ do |page_name|
  #
  # step definition in webrat_steps.rb
  #
  def path_to(page_name)
    case page_name
    
    when /the homepage/
      '/'
    when /the new external service page/
      new_external_service_path

    when /the new external servivice page/
      new_external_servivice_path

    when /the new session page/
      new_session_path


    when /the login page/
      login_path

    when /OAuth Authorize Endpoint/
      oauth_authorize_path

    when /the OAuth authorize page/
      oauth_authorize_path

    when /the password change page/
      password_path
    when /the own password change page/
      own_password_path
      
    when /the new organisation page/
      new_organisation_path
      
    # Role
    when /the new role page/
      new_role_path(@school)
    when /the edit role page/
      edit_role_path(@school)
    when /the roles list page/
      roles_path(@school)

    # User path
    when /the new user page/
      new_user_path(@school)
    when /the edit user page/
      edit_user_path(@school)
    when /the user page/
      user_path(@school)
    when /the new user import page/
      new_users_import_path(@school)

    # Group path
    when /the group page/
      group_path(@school)
    when /the new group page/
      new_group_path(@school)
    when /the groups list page/
      groups_path(@school)
      
    # School path  
    when /the school page/
      school_path(@school)
    when /the new school page/
      new_school_path
    when /the edit school page/
      edit_school_path
    when /the schools list page/
      schools_path


    # Add more mappings here.
    # Here is a more fancy example:
    #
    #   when /^(.*)'s profile page$/i
    #     user_profile_path(User.find_by_login($1))

    else
      raise "Can't find mapping from \"#{page_name}\" to a path.\n" +
        "Now, go and add a mapping in #{__FILE__}"
    end
  end
end

World(NavigationHelpers)
