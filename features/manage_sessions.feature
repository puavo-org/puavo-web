Feature: Manage sessions
  In order to [goal]
  [stakeholder]
  wants [behaviour]

  Background:
    Given a new school and group with names "School 1", "Class 4" on the "example" organisation
    And the following roles:
    | displayName |
    | Staff       |
    And the following users:
      | givenName | sn     | uid   | password | school_admin | role_name | eduPersonAffiliation |
      | Pavel     | Taylor | pavel | secret   | true         | Staff     | Staff                |

  Scenario: Login
    Given I am on the login page
    And I fill in "Login" with "pavel"
    And I fill in "Password" with "secret"
    And I press "Login"
    Then I should see "Login successful!"

  Scenario: Login with incorrect username
    Given I am on the login page
    And I fill in "Login" with "something"
    And I fill in "Password" with "secret"
    And I press "Login"
    Then I should see "Login failed!"

  Scenario: Login with incorrect password
    Given I am on the login page
    And I fill in "Login" with "pavel"
    And I fill in "Password" with "secrett"
    And I press "Login"
    Then I should see "Login failed!"
    When I fill in "Login" with "pavel"
    And I fill in "Password" with ""
    Then I should see "Login failed!"
