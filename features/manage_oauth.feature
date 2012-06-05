Feature: OAuth login
  In order to [goal]
  [stakeholder]
  wants [behaviour]

  Background:
    Given the following oauth client:
      | displayName      | userPassword            | puavoOAuthScope   |
      | Example software | zK7oEm34gYk3hA54DKX8da4 | read:presonalInfo |
    And a new school and group with names "Example school 1", "Class 1" on the "example" organisation
    And a new role with name "Class 1" and which is joined to the "Class 1" group to "Example school 1" school
    And the following users:
    | givenName | sn     | uid         | password | role_name | puavoEduPersonAffiliation | school_admin |
    | Joe       | Bloggs | joe.bloggs  | secret   | Class 1   | Student                   | false        |

  Scenario: I Can get user data with OAuth Access Token
    Given I have been redirected to the OAuth authorize page from "Example software"
    Then I should be on the login page
    When I fill in "Username" with "joe.bloggs"
    And I fill in "Password" with "secret"
    And I press "Login"
    # When I press "ok"
    Then I should get OAuth Authorization Code
    And I should get OAuth Access Token with Authorization Code
    And I should get "joe.bloggs" information with Access Token
    And I should get a new Access Token and a new Refresh Token with existing Refresh Token
    # New Access Token should work
    And I should get "joe.bloggs" information with Access Token

  Scenario: I try to get an Access Token with expired Authorization Code
    Given I have been redirected to the OAuth authorize page from "Example software"
    Then I should be on the login page
    When I fill in "Username" with "joe.bloggs"
    And I fill in "Password" with "secret"
    And I press "Login"
    Then I should get OAuth Authorization Code
    Given I wait 5 hours
    Then I should not get OAuth Access Token with expired Authorization Code

  Scenario: I try to get user data with expired Access Token
    Given I have been redirected to the OAuth authorize page from "Example software"
    Then I should be on the login page
    When I fill in "Username" with "joe.bloggs"
    And I fill in "Password" with "secret"
    And I press "Login"
    # When I press "ok"
    Then I should get OAuth Authorization Code
    And I should get OAuth Access Token with Authorization Code
    Given I wait 1 year
    Then I should not get "joe.bloggs" information with expired Access Token

  Scenario: I try to get new Access Token with expired Refresh Token
    Given I have been redirected to the OAuth authorize page from "Example software"
    Then I should be on the login page
    When I fill in "Username" with "joe.bloggs"
    And I fill in "Password" with "secret"
    And I press "Login"
    Then I should get OAuth Authorization Code
    And I should get OAuth Access Token with Authorization Code
    Given I wait 10 years
    Then I should not get a new Access Token and a new refresh Token with expired refresh Token
