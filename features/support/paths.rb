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
    when /the new LDAP service page/
      new_ldap_service_path

    when /the new session page/
      new_session_path

    when /the login page/
      login_path

    when /the password change page with changing user (.+) and changed user (.+)/
      password_path + "?changing=#{$1}&changed=#{$2}"
    when /the password change page/
      password_path
    when /the own password change page with changing user (.+)/
      own_password_path + "?changing=#{$1}"
    when /the own password change page/
      own_password_path
    when /the forgot password page/
      forgot_password_path
    when /the own password change by token page/
      reset_password_path(@jwt)

    when /the new organisation page/
      new_organisation_path
    when /the organisation page/
      organisation_path

    when /printer permissions page/
      printer_permissions_path(@school)

    # User path
    when /the new user page/
      new_user_path(@school)
    when /the edit user page/
      edit_user_path(@school)
    when /the user page/
      user_path(@school)
    when /the new user import page/
      new_users_import_path(@school)
    when /the school users list page/
      users_path(@school)

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
    # Profile path
    when /the edit profile page/
      edit_profile_path
    when /the server list page/
      servers_path

    # Device path
    when /the devices list page/
      devices_path(@school)
    when /the new printer device page/
      new_device_path(@school, :device_type => "printer")
    when /the new other device page/
      new_device_path(@school, :device_type => "other")
    when /the device page of a non-existent school/
      '/devices/99999999/devices'

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
