Feature: Manage sessions
  In order to [goal]
  [stakeholder]
  wants [behaviour]

  Background:
    Given a new school and group with names "School 1", "Class 4" on the "example" organisation
    And the following users:
      | givenName | sn     | uid   | password | school_admin | puavoEduPersonAffiliation |
      | Pavel     | Taylor | pavel | secret   | true         | admin                     |

  Scenario: Login
    Given I am on the login page
    And I fill in "Username" with "pavel"
    And I fill in "Password" with "secret"
    And I press "Login"
    Then I should see "Pavel Taylor"
    And I should not see "Login failed!"
    And I should not see "LDAP services"

  Scenario: Login with organisation owner
    Given I am on the login page
    And I fill in "Username" with "cucumber"
    And I fill in "Password" with "cucumber"
    And I press "Login"
    Then I should see "cucumber"
    And I should not see "Login failed!"
    And I should see "LDAP services"

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

  Scenario: Expired user account cannot login
    # Set an expiration time for Pavel's account
    Given I am logged in as "cucumber" with password "cucumber"
    And I am on the show user page with "pavel"
    When I follow "Edit..."
    And I set the expiration time to 1754900001
    And I press "Update"
    # Then try to log in as Pavel
    Given I am logged out
    And I am on the login page
    And I fill in "Username" with "pavel"
    And I fill in "Password" with "secret"
    And I press "Login"
    Then I should see "Your account has expired"
