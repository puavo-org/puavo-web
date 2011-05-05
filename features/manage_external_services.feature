Feature: Manage external services
  In order to external services can be use in Puavo LDAP-authentication
  Organisation owner should be able to
  add and remove System Accounts

  Background:
    Given a new school and group with names "Example school 1", "Class 1" on the "example" organisation
    And the following schools:
    | displayName              | cn        |
    | Greenwich Steiner School | greenwich |
    And a new role with name "Class 1" and which is joined to the "Class 1" group to "Greenwich Steiner School" school
    And I am logged in as "example" organisation owner

  
  Scenario: Add new external service
    Given I follow "External service"
    And I follow "New"
    When I fill in "Service Identifier" with "uid 1"
    And I fill in "Description" with "description 1"
    And I fill in "Password" with "password 1"
    And I press "Create"
    Then I should see "uid 1"
    And I should see "description 1"
    And I should see "password 1"

  Scenario: Delete external service
    Given the following external services:
      | uid   | description   | userPassword |
      | uid 1 | description 1 | password 1   |
      | uid 2 | description 2 | password 2   |
      | uid 3 | description 3 | password 3   |
      | uid 4 | description 4 | password 4   |
    When I delete the 3rd external service
    Then I should see the following external services:
      | Service Identifier | Description   |
      | uid 1              | description 1 |
      | uid 2              | description 2 |
      | uid 4              | description 4 |

  Scenario: Edit external service
    Given the following external services:
      | uid   | description   | userPassword |
      | uid 1 | description 1 | password 1   |
      | uid 2 | description 2 | password 2   |
      | uid 3 | description 3 | password 3   |
      | uid 4 | description 4 | password 4   |
    And I follow "External service"
    And I follow "uid 1"
    And I follow "Edit"
    #When I fill in "Service Identifier" with "uid 2"
    And I fill in "Description" with "test description one"
    And I fill in "Password" with "test password one"
    And I press "Update"
    #Then I should see "test uid one"
    And I should see "test description one"
    And I should see "test password one"
