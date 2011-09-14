Feature: Manage schools
  In order to split organisation
  As a organisation owner
  I want to manage the schools

  Background:
    Given a new school and group with names "Example school 1", "Class 1" on the "example" organisation
    And a new role with name "Class 1" and which is joined to the "Class 1" group to "Example school 1" school
    And the following schools:
    | displayName              | cn        |
    | Greenwich Steiner School | greenwich |
    And a new role with name "Class 1" and which is joined to the "Class 1" group to "Greenwich Steiner School" school
    And I am logged in as "example" organisation owner

  Scenario: Add new school to organisation
    Given I am on the new school page
    Then I should see "New school"
    When I fill in the following:
    | School name        | Bourne School                                                                  |
    | Name prefix        | bourne                                                                         |
    | School's home page | www.bourneschool.com                                                           |
    | Description        | The Bourne Community School is a county school for boys and girls aged 4 to 7. |
    | Group name         | bourne                                                                         |
    | Phone number       | 0123456789                                                                     |
    | Fax number         | 9876543210                                                                     |
    | Locality           | England                                                                        |
    | Street             | Raymond Mays Way                                                               |
    | Post Office Box    | 123                                                                            |
    | Postal address     | 12345                                                                          |
    | Postal code        | 54321                                                                          |
    | State              | East Midlands                                                                  |
    And I attach the file at "features/support/test.jpg" to "image"
    And I press "Create"
    Then I should not see "error"
    # Translation missing
    And I should not see "en, activeldap, attributes, school"
    And I should see the following:
    |                                                                                |
    | Bourne School                                                                  |
    | School's home page                                                             |
    | Raymond Mays Way                                                               |
    | 123                                                                            |
    | 12345                                                                          |
    | 54321                                                                          |
    And I should see "School was successfully created."

  Scenario: Add new school to organisation without names
    Given I am on the new school page
    And I press "Create"
    Then I should see "Failed to create school!"
    # And I should see "School name can't be blank"
    And I should see "Group name can't be blank"
    When I fill in "Group name" with "Example School"
    And I press "Create"
    Then I should see "Group name include invalid characters (allowed characters is a-z0-9-)"
    When I fill in "Group name" with "example-school"
    And I fill in "Name prefix" with "example prefix"
    And I press "Create"
    Then I should see "Name prefix include invalid characters (allowed characters is a-z0-9-)"
    

  Scenario: Edit school and set empty names
    Given I am on the school page with "Greenwich Steiner School"
    And I follow "Edit"
    When I fill in "School name" with ""
    And I fill in "Group name" with ""
    And I press "Update"
    Then I should see "School cannot be saved!"
    # And I should see "School name can't be blank"
    And I should see "Group name can't be blank"

  Scenario: Change school name
    Given I am on the school page with "Greenwich Steiner School"
    And I follow "Edit"
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
    And I follow "Destroy"
    And I am on the show school page with "Example school 1"
    And I follow "Destroy"
    When I go to the schools list page
    Then I should see "Listing schools"
    And I should see "New school"

  Scenario: Schools list page when we have only one school and user is not organisation owner
    Given the following users:
      | givenName | sn     | uid   | password | school_admin | role_name | puavoEduPersonAffiliation | school                   |
      | Pavel     | Taylor | pavel | secret   | true         | Class 1   | admin                     | Greenwich Steiner School | 
    And I follow "Logout"
    And I am logged in as "pavel" with password "secret"
    When I go to the schools list page
    Then I should be on the "Greenwich Steiner School" school page

  Scenario: Delete school
    Given the following schools:
    | displayName   | cn          |
    | Test School 1 | testschool1 |
    And I am on the show school page with "Test School 1"
    When I follow "Destroy"
    Then I should see "School was successfully destroyed."

  Scenario: Delete school when it still contains the users, groups and roles
    Given a new school and group with names "Test School 1", "Group 1" on the "example" organisation
    And the following roles:
    | displayName | cn    |
    | Role 1      | role1 |
    And the following users:
    | givenName | sn     | uid   | password | role_name | puavoEduPersonAffiliation | school |
    | User 1    | User 1 | user1 | secret   | Role 1    | student                   | Test   | 
    And I am on the show school page with "Test School 1"
    When I follow "Destroy"
    Then I should see "School was not successfully destroyed. Users, roles and groups must be removed before school"
    And I should be on the school page
  
  Scenario: Add school management access rights to the user
    Given the following users:
    | givenName | sn     | uid   | password | role_name | puavoEduPersonAffiliation | school                   |
    | Pavel     | Taylor | pavel | secret   | Class 1   | admin                     | Greenwich Steiner School |
    And I am on the school page with "Greenwich Steiner School"
    When I follow "Admins"
    Then I should see "Greenwich Steiner School admin users"
    And  I should see "Add management access rights"
    And I should not see "Pavel Taylor (Greenwich Steiner School)" on the school admin list
    And I should be added school management access to the "Pavel Taylor (Greenwich Steiner School)"
    When I follow "Add" on the "Pavel Taylor" user
    Then I should see "Pavel Taylor (Greenwich Steiner School) is now admin users"
    And I should see "Pavel Taylor (Greenwich Steiner School)" on the school admin list
    And I should not be added school management access to the "Pavel Taylor (Greenwich Steiner School)"
    And the memberUid should include "pavel" on the "Domain Admins" samba group


  Scenario: Remove school management access rights from the user
    Given the following users:
    | givenName | sn     | uid   | password | role_name | puavoEduPersonAffiliation | school           | school_admin |
    | Pavel     | Taylor | pavel | secret   | Class 1   | admin                     | Example school 1 | true         |
    And I am on the school page with "Greenwich Steiner School"
    When I follow "Admins"
    And I follow "Add" on the "Pavel Taylor" user
    Then I should see "Pavel Taylor (Greenwich Steiner School) is now admin users"
    And I should see "Pavel Taylor (Example school 1)" on the school admin list
    And I should not be added school management access to the "Pavel Taylor (Example school 1)"
    When I follow "Remove" on the "Pavel Taylor" user
    Then I should see "Pavel Taylor (Greenwich Steiner School) is no longer admin user on this school"
    And I should not see "Pavel Taylor (Example school 1)" on the school admin list
    And I should be added school management access to the "Pavel Taylor (Example school 1)"
    And the memberUid should include "pavel" on the "Domain Admins" samba group
    When I am on the school page with "Example school 1"
    And I follow "Admins"
    And I follow "Remove" on the "Pavel Taylor" user
    Then I should see "Pavel Taylor (Example school 1) is no longer admin user on this school"
    And the memberUid should not include "pavel" on the "Domain Admins" samba group
    

  Scenario: School management access can be added only if user type is admin
    Given the following users:
    | givenName | sn     | uid   | password | role_name | puavoEduPersonAffiliation | school                   |
    | Pavel     | Taylor | pavel | secret   | Class 1   | admin                     | Greenwich Steiner School |
    | Ben       | Mabey  | ben   | secret   | Class 1   | staff                     | Greenwich Steiner School |
    And I am on the school page with "Greenwich Steiner School"
    When I follow "Admins"
    Then I should be added school management access to the "Pavel Taylor (Greenwich Steiner School)"
    And I should not be added school management access to the "Ben Mabey (Greenwich Steiner School)"
    When I try to add "Ben Mabey" to admin user on the "Greenwich Steiner School" school
    Then I should not see "Ben Mabey (Greenwich Steiner School) is now admin users"
    And I should not see "Ben Mabey (Greenwich Steiner School)" on the school admin list
    And I should see "School management access rights can be added only if type of user is admin"

  Scenario: Check school special ldap attributes
    Then I should see the following special ldap attributes on the "School" object with "Example school 1":
    | sambaSID                 | "^S[-0-9+]"                                                                                                                   |
    | sambaGroupType           | "2"                                                                                                                           |

  Scenario: School dashboard page with admin user
    Given the following users:
      | givenName | sn     | uid   | password | school_admin | role_name | puavoEduPersonAffiliation | school                   |
      | Pavel     | Taylor | pavel | secret   | true         | Class 1   | admin                     | Greenwich Steiner School |
    And I am logged in as "pavel" with password "secret"
    And I am on the school page with "Greenwich Steiner School"
    Then I should not see "Admins"
