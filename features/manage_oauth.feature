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

  Scenario: User logged in the application
    Given I have been redirected to the OAuth authorize page from "Example software"
    Then I should be on the login page
    When I fill in "Username" with "joe.bloggs"
    And I fill in "Password" with "secret"
    And I press "Login"
    # When I press "ok"
    Then I should get OAuth authorization code
    And I should get OAuth access token with authorization code
    And I should get "joe.bloggs" information with access token
    And I should get a new access token and a new refresh token with existing refresh token
    # New access token should work
    And I should get "joe.bloggs" information with access token

