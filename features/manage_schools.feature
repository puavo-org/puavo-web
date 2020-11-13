Feature: Manage schools
  In order to split organisation
  As a organisation owner
  I want to manage the schools

  Background:
    Given a new school and group with names "Example school 1", "Teacher" on the "example" organisation
    And the following schools:
    | displayName              | cn        |
    | Greenwich Steiner School | greenwich |
    And I am logged in as "example" organisation owner

  Scenario: Add new school to organisation
    Given I am on the new school page
    Then I should see "New school"
    When I fill in the following:
    | School name                         | Bourne School                                                                  |
    | Name prefix                         | bourne                                                                         |
    | School's home page                  | www.bourneschool.com                                                           |
    | Description                         | The Bourne Community School is a county school for boys and girls aged 4 to 7. |
    | Group name                          | bourne                                                                         |
    | Phone number                        | 0123456789                                                                     |
    | Fax number                          | 9876543210                                                                     |
    | Locality                            | England                                                                        |
    | Street                              | Raymond Mays Way                                                               |
    | Post Office Box                     | 123                                                                            |
    | Postal address                      | 12345                                                                          |
    | Postal code                         | 54321                                                                          |
    | State                               | East Midlands                                                                  |
    | Desktop Image                       | presice-20121023                                                               |
    | school[puavoBillingInfo][]          | school_base:500                                                                |
    | Tags                                | testag1 testag2 testag2                                                        |
    | school_fs_0                         | nfs3                                                                           |
    | school_path_0                       | 10.0.0.1/share                                                                 |
    | school_mountpoint_0                 | /home/share                                                                    |
    | school_options_0                    | -o rw                                                                          |
    | school[puavoImageSeriesSourceURL][] | http://foobar.puavo.net/trusty                                                 |
    And I fill in "PuavoConf settings" with:
      """
      {
        "puavo.admin.personally_administered": true,
        "puavo.autopilot.enabled": false,
        "puavo.desktop.vendor.logo": "/usr/share/puavo-art/logo.png",
        "puavo.login.external.enabled": false
      }
      """
    And I attach the file at "features/support/test.jpg" to "Image"
    And I select "English (United States)" from "Language"
    And I choose "school_puavoAutomaticImageUpdates_false"
    And I select "13" from "school[puavoDeviceOnHour]"
    And I select "19" from "school[puavoDeviceOffHour]"
    And I choose "school_puavoDeviceAutoPowerOffMode_default"
    And I choose "school_puavoDeviceAutoPowerOffMode_off"
    And I choose "school_puavoDeviceAutoPowerOffMode_custom"
    And I press "Create"
    Then I should not see "error"
    # Translation missing
    And I should not see "en, activeldap, attributes, school"
    And I should see the following:
    |                                 |
    | Bourne School                   |
    | School's home page              |
    | Raymond Mays Way                |
    | 123                             |
    | 12345                           |
    | 54321                           |
    | presice-20121023                |
    | school_base:500                 |
    | testag1 testag2                 |
    | nfs3                            |
    | 10.0.0.1/share                  |
    | /home/share                     |
    | -o rw                           |
    | English (United States)         |
    | Automatic image updates No      |
    | Auto power off mode             |
    | Daytime start                   |
    | Daytime end                     |
    | http://foobar.puavo.net/trusty  |
    And I should see "School was successfully created."
    And I should see school image of "Bourne School"
    And I should see the following special ldap attributes on the "School" object with "Bourne School":
    | preferredLanguage | "en" |
    And I should see the following puavo-conf values:
    | puavo.admin.personally_administered | true                            |
    | puavo.autopilot.enabled             | false                           |
    | puavo.desktop.vendor.logo           | /usr/share/puavo-art/logo.png   |
    | puavo.login.external.enabled        | false                           |

  Scenario: Add new school to organisation without names
    Given I am on the new school page
    And I press "Create"
    Then I should see "Failed to create school!"
    # And I should see "School name can't be blank"
    And I should see "Group name can't be blank"
    When I fill in "Group name" with "Example School"
    And I press "Create"
    Then I should see "Group name contains invalid characters (allowed characters are a-z0-9-)"
    When I fill in "Group name" with "example-school"
    And I fill in "Name prefix" with "example prefix"
    And I press "Create"
    Then I should see "Name prefix contains invalid characters (allowed characters are a-z0-9-)"


  Scenario: Edit school and set empty names
    Given I am on the school page with "Greenwich Steiner School"
    And I follow "Edit..."
    When I fill in "School name" with ""
    And I fill in "Group name" with ""
    And I press "Update"
    Then I should see "School cannot be saved!"
    # And I should see "School name can't be blank"
    And I should see "Group name can't be blank"

  Scenario: Change school name
    Given I am on the school page with "Greenwich Steiner School"
    And I follow "Edit..."
    When I fill in "School name" with "St. Paul's"
    And I press "Update"
    Then I should see "St. Paul's"
    And I should see "School was successfully updated."


  Scenario: Add duplicate school or group abbreviation
    Given the following groups:
    | displayName | cn     |
    | Class 4     | class4 |
    And I am on the new school page
    When I fill in "School name" with "Greenwich Steiner School"
    And I fill in "Group name" with "greenwich"
    And I press "Create"
    Then I should not see "School was successfully created"
    Then I should see "Group name has already been taken"
    When I fill in "School name" with "Greenwich Steiner School"
    And I fill in "Group name" with "class4"
    And I press "Create"
    Then I should not see "School was successfully created"
    Then I should see "Group name has already been taken"

  Scenario: Listing schools
    Given I am on the schools list page
    Then I should see "Greenwich Steiner School"
    And I should see "Example school 1"

  Scenario: Schools list page when we have only one school and user is organisation ower
    Given I am on the show school page with "Greenwich Steiner School"
    And I follow "Delete school"
    And I am on the show school page with "Example school 1"
    And I follow "Delete school"
    When I go to the schools list page
    Then I should see "Example Organisation" within "#schoolsTitle"
    And I should see "New school"

  Scenario: Schools list page when we have only one school and user is not organisation owner
    Given the following users:
      | givenName | sn     | uid   | password | school_admin | puavoEduPersonAffiliation | school                   |
      | Pavel     | Taylor | pavel | secret   | true         | admin                     | Greenwich Steiner School |
    And I follow "Logout"
    And I am logged in as "pavel" with password "secret"
    When I go to the schools list page
    Then I should be on the "Greenwich Steiner School" school page

  Scenario: Delete school
    Given the following schools:
    | displayName   | cn          |
    | Test School 1 | testschool1 |
    And I am on the show school page with "Test School 1"
    When I follow "Delete school"
    Then I should see "School was successfully removed."

  Scenario: Delete school when it still contains the users and groups
    Given a new school and group with names "Test School 1", "Group 1" on the "example" organisation
    And the following users:
    | givenName | sn     | uid   | password | puavoEduPersonAffiliation | school        |
    | User 1    | User 1 | user1 | secret   | student                   | Test School 1 |
    And I am on the show school page with "Test School 1"
    When I follow "Delete school"
    Then I should see "The school was not removed. Its users, groups, devices and boot servers must be removed first."
    And I should be on the school page

  Scenario: Deleting a school when it still contains devices should fail
    Given I am on the new school page
    Then I should see "New school"
    When I fill in the following:
    | School name | Condemned School |
    | Group name  | condemnedschool  |
    And I press "Create"
    Then I should see "School was successfully created."
    Given I am on the new other device page with "Condemned School"
    When I fill in "Hostname" with "testdevice1"
    And I press "Create"
    Then I should see "Device was successfully created."
    Given I am on the school page with "Condemned School"
    Then I should see "School's home page"
    When I follow "Delete school"
    Then I should see "The school was not removed. Its users, groups, devices and boot servers must be removed first."
    Given I am on the devices list page with "Condemned School"
    And I press "Remove" on the "testdevice1" row
    Then I should see "List of devices"
    Given I am on the school page with "Condemned School"
    When I follow "Delete school"
    Then I should see "School was successfully removed."
    And I should see "Example Organisation" within "#schoolsTitle"


  Scenario: Add school management access rights to the user
    Given the following users:
    | givenName | sn     | uid   | password | puavoEduPersonAffiliation | school                   |
    | Pavel     | Taylor | pavel | secret   | admin                     | Greenwich Steiner School |
    And I am on the show user page with "pavel"
    Then I should not see "The user is an admin of this school"
    Given I am on the school page with "Greenwich Steiner School"
    When I follow "Admins"
    Then I should see "Greenwich Steiner School admin users"
    And  I should see "Add management access rights"
    And I should not see "Pavel Taylor (pavel) (Greenwich Steiner School)" on the school admin list
    And I should be added school management access to the "Pavel Taylor (pavel) (Greenwich Steiner School)"
    When I follow "Add" on the "Pavel Taylor" user
    Then I should see "Pavel Taylor (Greenwich Steiner School) is now an admin user"
    And I should see "Pavel Taylor (pavel) (Greenwich Steiner School)" on the school admin list
    And I should not be added school management access to the "Pavel Taylor (Greenwich Steiner School)"
    And the memberUid should include "pavel" on the "Domain Admins" samba group
    Given I am on the show user page with "pavel"
    Then I should see "The user is an admin of this school"


  Scenario: Remove school management access rights from the user
    Given the following users:
    | givenName | sn     | uid   | password | puavoEduPersonAffiliation | school           | school_admin |
    | Pavel     | Taylor | pavel | secret   | admin                     | Example school 1 | true         |
    And I am on the show user page with "pavel"
    Then I should see "The user is an admin of this school"
    Then I am on the school page with "Greenwich Steiner School"
    When I follow "Admins"
    And I follow "Add" on the "Pavel Taylor" user
    Then I should see "Pavel Taylor (Greenwich Steiner School) is now an admin user"
    And I should see "Pavel Taylor (pavel) (Example school 1)" on the school admin list
    And I should not be added school management access to the "Pavel Taylor (pavel) (Example school 1)"
    When I follow "Remove" on the "Pavel Taylor" user
    Then I should see "Pavel Taylor (Greenwich Steiner School) is no longer an admin user in this school"
    And I should not see "Pavel Taylor (pavel) (Example school 1)" on the school admin list
    And I should be added school management access to the "Pavel Taylor (pavel) (Example school 1)"
    And the memberUid should include "pavel" on the "Domain Admins" samba group
    When I am on the school page with "Example school 1"
    And I follow "Admins"
    And I follow "Remove" on the "Pavel Taylor" user
    Then I should see "Pavel Taylor (Example school 1) is no longer an admin user in this school"
    And the memberUid should not include "pavel" on the "Domain Admins" samba group
    Given I am on the show user page with "pavel"
    Then I should not see "The user is an admin of this school"


  Scenario: School management access can be added only if user type is admin
    Given the following users:
    | givenName | sn     | uid   | password | puavoEduPersonAffiliation | school                   |
    | Pavel     | Taylor | pavel | secret   | admin                     | Greenwich Steiner School |
    | Ben       | Mabey  | ben   | secret   | staff                     | Greenwich Steiner School |
    And I am on the school page with "Greenwich Steiner School"
    When I follow "Admins"
    Then I should be added school management access to the "Pavel Taylor (pavel) (Greenwich Steiner School)"
    And I should not be added school management access to the "Ben Mabey (ben) (Greenwich Steiner School)"
    When I try to add "Ben Mabey" to admin user on the "Greenwich Steiner School" school
    Then I should not see "Ben Mabey (Greenwich Steiner School) is now an admin user"
    And I should not see "Ben Mabey (ben) (Greenwich Steiner School)" on the school admin list
    And I should see "School management access rights can be added only if the type of the user is admin"

  Scenario: Check school special ldap attributes
    Then I should see the following special ldap attributes on the "School" object with "Example school 1":
    | sambaSID                 | "^S[-0-9+]"                                                                                                                   |
    | sambaGroupType           | "2"                                                                                                                           |

  Scenario: School dashboard page with admin user
    Given the following users:
      | givenName | sn     | uid   | password | school_admin | puavoEduPersonAffiliation | school                   |
      | Pavel     | Taylor | pavel | secret   | true         | admin                     | Greenwich Steiner School |
    And I am logged in as "pavel" with password "secret"
    And I am on the school page with "Greenwich Steiner School"
    Then I should not see "Admins"

  Scenario: Give the school a non-image file as the image
    Given I am on the new school page
    Then I should see "New school"
    When I attach the file at "features/support/hello.txt" to "Image"
    And I press "Create"
    Then I should see "Failed to save the image"

Scenario: Set, edit and check the school code
    Given I am on the new school page
    Then I should see "New school"
    When I fill in the following:
    | School name                         | Test school |
    | Group name                          | test        |
    | School code                         | testcode    |
    And I press "Create"
    Then I should see "School was successfully created"
    And I should see "testcode"
    When I follow "Edit..."
    And I fill in "School code" with "foobar"
    And I press "Update"
    Then I should see "School was successfully updated."
    And I should see "foobar"
    When I follow "Edit"
    And I fill in "School code" with ""
    And I press "Update"
    Then I should see "School was successfully updated."

Scenario: Set the school code for an existing school
    Given I am on the new school page
    Then I should see "New school"
    When I fill in the following:
    | School name                         | Test school 2 |
    | Group name                          | test2         |
    And I press "Create"
    Then I should see "School was successfully created"
    When I follow "Edit..."
    And I fill in "School code" with "bazquux"
    And I press "Update"
    Then I should see "School was successfully updated."
    And I should see "bazquux"

  Scenario: .img extension is removed from desktop image names
    Given I am on the school page with "Greenwich Steiner School"
    And I follow "Edit..."
    And I fill in "Desktop Image" with "example_image.img"
    And I press "Update"
    # All "I should see" and "I should not see" checks are just simple
    # substring searches. If there's "example_image.img" on the page,
    # then it will match to "example_image". So we must check for the
    # absence of the extension itself.
    Then I should not see ".img"
    When I follow "Edit..."
    And I fill in "Desktop Image" with "example_image_2"
    And I press "Update"
    Then I should see "example_image_2"
