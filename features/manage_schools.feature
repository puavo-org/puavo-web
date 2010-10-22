Feature: Manage schools
  In order to split organisation
  As a organisation owner
  I want to manage the schools

  Background:
    Given a new school with names "Example school 1", "Class 1" on the "example" organisation
    And the following schools:
    | displayName              | cn        |
    | Greenwich Steiner School | greenwich |
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
    And I press "Create"
    Then I should not see "error"
    # Translation missing
    And I should not see "en, activeldap, attributes, school"
    And I should see the following:
    |                                                                                |
    | Bourne School                                                                  |
    | bourne                                                                         |
    | www.bourneschool.com                                                           |
    | The Bourne Community School is a county school for boys and girls aged 4 to 7. |
    | bourne                                                                         |
    | 0123456789                                                                     |
    | 9876543210                                                                     |
    | England                                                                        |
    | Raymond Mays Way                                                               |
    | 123                                                                            |
    | 12345                                                                          |
    | 54321                                                                          |
    | East Midlands                                                                  |

  Scenario: Change school name
    Given I am on the school page with "Greenwich Steiner School"
    And I follow "Edit"
    When I fill in "School name" with "St. Paul's"
    And I press "Update"
    Then I should see "St. Paul's"

  Scenario: Add duplicate school or group abbreviation
    Given the following groups:
    | displayName | cn     |
    | Class 4     | class4 |
    And I am on the new school page
    When I fill in "School name" with "Greenwich Steiner School"
    And I fill in "Group name" with "greenwich"
    And I press "Create"
    Then I should not see "School was successfully created"
    Then I should see "Name has already been taken"
    When I fill in "School name" with "Greenwich Steiner School"
    And I fill in "Group name" with "class4"
    And I press "Create"
    Then I should not see "School was successfully created"
    Then I should see "Name has already been taken"

  Scenario: Listing schools
    Given I am on the schools list page
    Then I should see "Greenwich Steiner School"
    And I should see "Example school 1"

  Scenario: Add school management access rights to the user
    Given the following users:
    | givenName | sn     | uid   | password | role_name   | puavoEduPersonAffiliation | school                   |
    | Pavel     | Taylor | pavel | secret   | Maintenance | admin                     | Greenwich Steiner School |
    And I am on the school page with "Greenwich Steiner School"
    When I follow "Admins"
    Then I should see "Greenwich Steiner School admin users"
    And  I should see "School management access rights can be added to the following users"
    And I should not see "Pavel Taylor (Greenwich Steiner School)" on the school admin list
    And I should be added school management access to the "Pavel Taylor (Greenwich Steiner School)"
    When I follow "Add" on the "Pavel Taylor" user
    Then I should see "Pavel Taylor (Greenwich Steiner School) is now admin users"
    And I should see "Pavel Taylor (Greenwich Steiner School)" on the school admin list
    And I should not be added school management access to the "Pavel Taylor (Greenwich Steiner School)"
    And the memberUid should include "pavel" on the "Domain Admins" samba group


  Scenario: Remove school management access rights from the user
    Given the following users:
    | givenName | sn     | uid   | password | role_name   | puavoEduPersonAffiliation | school                   | school_admin |
    | Pavel     | Taylor | pavel | secret   | Maintenance | admin                     | Greenwich Steiner School | true         |
    And I am on the school page with "Greenwich Steiner School"
    When I follow "Admins"
    Then I should see "Pavel Taylor (Greenwich Steiner School)" on the school admin list
    And I should not be added school management access to the "Pavel Taylor (Greenwich Steiner School)"
    When I follow "Remove" on the "Pavel Taylor" user
    Then I should see "Pavel Taylor (Greenwich Steiner School) is no longer admin user on this school"
    And I should not see "Pavel Taylor (Greenwich Steiner School)" on the school admin list
    And I should be added school management access to the "Pavel Taylor (Greenwich Steiner School)"
    And the memberUid should not include "pavel" on the "Domain Admins" samba group

  Scenario: School management access can be added only if user type is admin
    Given the following users:
    | givenName | sn     | uid   | password | role_name   | puavoEduPersonAffiliation | school                   |
    | Pavel     | Taylor | pavel | secret   | Maintenance | admin                     | Greenwich Steiner School |
    | Ben       | Mabey  | ben   | secret   | Maintenance | staff                     | Greenwich Steiner School |
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

