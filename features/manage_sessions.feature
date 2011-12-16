Feature: Manage sessions
  In order to [goal]
  [stakeholder]
  wants [behaviour]

  Background:
    Given the following schools:
    | displayName      | cn            |
    | Example school 1 | exampleschool |
    And the following roles:
    | displayName | cn      | puavoEduPersonAffiliation |
    | Staff       | staff   | staff                     |
    And the following users:
      | givenName | sn     | uid   | password | school_admin | roles | school           |
      | Pavel     | Taylor | pavel | secret   | true         | Staff | Example school 1 |

  Scenario: Login
    Given I am on the login page
    And I fill in "Username" with "pavel"
    And I fill in "Password" with "secret"
    And I press "Login"
    Then I should see "Login successful!"
    And I should not see "Servers"

  Scenario: Login with organisation owner
    Given I am on the login page
    And I fill in "Username" with "cucumber"
    And I fill in "Password" with "cucumber"
    And I press "Login"
    Then I should see "Login successful!"
    And I should see "Servers"

  Scenario: Login with incorrect username
    Given I am on the login page
    And I fill in "Username" with "something"
    And I fill in "Password" with "secret"
    And I press "Login"
    Then I should see "Login failed!"

  Scenario: Login with incorrect password
    Given I am on the login page
    And I fill in "Username" with "pavel"
    And I fill in "Password" with "secrett"
    And I press "Login"
    Then I should see "Login failed!"
    When I fill in "Username" with "pavel"
    And I fill in "Password" with ""
    Then I should see "Login failed!"
