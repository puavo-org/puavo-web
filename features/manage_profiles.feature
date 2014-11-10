Feature: Manage profile
  In order to [goal]
  [stakeholder]
  wants [behaviour]

  Background:
    Given a new school and group with names "School 1", "Class 4" on the "example" organisation
    And a new role with name "Class 4" and which is joined to the "Class 4" group
    And the following roles:
      | displayName |
      | Teacher     |
      | Class 4     |
    And the following users:
      | givenName | surname | uid       | password   | puavoEduPersonAffiliation | role_name | school_admin |
      | Ken       | Jones   | ken.jones | secret     | teacher                   | Teacher   | true         |
      | Jane      | Doe     | jane.doe  | janesecret | student                   | Class 4   | false        |


  Scenario: School admin edit profile
    Given mock email confirm service for user "ken.jones" with email "ken.jones@opinsys.fi"
    When I am on the edit profile page
    Then I should be on the login page
    When I fill in "Username" with "ken.jones"
    And I fill in "Password" with "secret"
    And I press "Login"
    Then I should see "Login successful!"
    And I should see "Ken Jones"
    When I fill in "Email" with "ken.jones@opinsys.fi"
    And I fill in "Telephone number" with "+35814123456789"
    And I select "German (Switzerland)" from "Language"
    # FIXME: select field?
    # And I fill in "preferredLanguage" with "fi"
    # FIXME image field?
    # And I fill in "image" with ""
    # FIXME: use password controller?
    # And I fill in "password" with ""

    # FIXME image field?
    # And I fill in "background" with ""
    # FIXME following fields should be add to ldap
    # And I fill in "theme" with ""
    # And I fill in "mouse?" with ""

    When I press "Update"
    Then I should see "Profile was successfully updated"
    And I should see the following special ldap attributes on the "User" object with "ken.jones":
    | puavoLocale       | "de_CH.UTF-8" |
    | preferredLanguage | "de"          |
    And I should see "ken.jones@opinsys.fi"

  Scenario: Student edit profile
    When I am on the edit profile page
    Then I should be on the login page
    When I fill in "Username" with "jane.doe"
    And I fill in "Password" with "janesecret"
    And I press "Login"
    Then I should see "Login successful!"
    And I should see "Jane Doe"
    When I fill in "Telephone number" with "+35814987654321"
    And I attach the file at "features/support/test.jpg" to "Image"
    When I press "Update"
    Then I should see "Profile was successfully updated"

  Scenario: Student edit email address
    Given mock email confirm service for user "jane.doe" with email "jane.doe@opinsys.fi"
    When I am on the edit profile page
    Then I should be on the login page
    When I fill in "Username" with "jane.doe"
    And I fill in "Password" with "janesecret"
    And I press "Login"
    Then I should see "Login successful!"
    And I should see "Jane Doe"
    When I fill in "Email" with "jane.doe@opinsys.fi"
    When I press "Update"
    Then I should see "Profile was successfully updated"
    # FIXME: create "shoult not see..." step
    #And I should not see the following special ldap attributes on the "User" object with "jane.doe":
    #| mail | "jane.doe@opinsys.fi" |
    And I should see "Send email message to following email address(es)"
    And I should see "jane.doe@opinsys.fi"
