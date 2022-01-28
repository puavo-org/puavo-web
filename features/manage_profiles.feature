Feature: Manage profile
  In order to [goal]
  [stakeholder]
  wants [behaviour]

  Background:
    Given a new school and group with names "School 1", "Class 4" on the "example" organisation
    And the following users:
      | givenName | surname | uid       | password   | puavoEduPersonAffiliation | school_admin | mail                |
      | Ken       | Jones   | ken.jones | secret     | teacher                   | true         |                     |
      | Jane      | Doe     | jane.doe  | janesecret | student                   | false        | jane.doe@foobar.com |


  Scenario: School admin edit profile
    Given mock email confirm service for user "ken.jones" with email "ken.jones@puavo.net"
    When I am on the edit profile page
    Then I should be on the login page
    When I fill in "Username" with "ken.jones"
    And I fill in "Password" with "secret"
    And I press "Login"
    Then I should see "Ken Jones"
    When I fill in "Email" with "ken.jones@puavo.net"
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
    Then I should see "Your profile has been successfully updated"
    And I should see the following special ldap attributes on the "User" object with "ken.jones":
    | puavoLocale       | "de_CH.UTF-8" |
    | preferredLanguage | "de"          |

  Scenario: Student edit profile
    When I am on the edit profile page
    Then I should be on the login page
    When I fill in "Username" with "jane.doe"
    And I fill in "Password" with "janesecret"
    And I press "Login"
    Then I should see "Jane Doe"
    When I fill in "Telephone number" with "+35814987654321"
    And I attach the file at "features/support/test.jpg" to "Image"
    When I press "Update"
    Then I should see "Your profile has been successfully updated"
    And I should not see "A confirmation message will be soon sent to your new email address. Click it to verify your address."

  Scenario: Student edit email address
    When I am on the edit profile page
    Then I should be on the login page
    When I fill in "Username" with "jane.doe"
    And I fill in "Password" with "janesecret"
    And I press "Login"
    Then I should see "Jane Doe"
    When I fill in "Email" with "jane.doe@puavo.net"
    When I press "Update"
    Then I should see "Your profile has been successfully updated"
