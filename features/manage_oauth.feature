Feature: OAuth login
  In order to [goal]
  [stakeholder]
  wants [behaviour]

  Background:
    Given the following oauth client:
      | displayName      | puavoOAuthClientId             | userPassword            | puavoOAuthAccess  | ClientRedirectURI       |
      | Example software | fXLDE5FKas42DFgsfhRTfdlizK7oEm | zK7oEm34gYk3hA54DKX8da4 | read:presonalInfo | http://www.example2.com |
    And a new school and group with names "Example school 1", "Class 1" on the "example" organisation
    And the following schools:
    | displayName              | cn        |
    | Greenwich Steiner School | greenwich |
    And a new role with name "Class 1" and which is joined to the "Class 1" group to "Example school 1" school
    And the following users:
    | givenName | sn     | uid        | password | role_name | puavoEduPersonAffiliation |
    | Joe       | Bloggs | joe.bloggs | secret   | Class 1   | Student                   |
    #And I am logged in as "example" organisation owner

  Scenario: User logged in the application
    Given I have been redirected to the OAuth login page
    Then I should be on the OAuth login page
    When I fill in "Username" with "joe.bloggs"
    And I fill in "Password" with "secret"
    And I press "Login"
    Then I should get OAuth access code
    And I should get OAuth access token with access code
    And I should get "joe.bloggs" information with access token
