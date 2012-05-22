Feature: Manage users
  In order to [goal]
  [stakeholder]
  wants [behaviour]

  Background:
    Given a new school and group with names "Example school 1", "Class 1" on the "example" organisation
    And the following schools:
    | displayName              | cn        |
    | Greenwich Steiner School | greenwich |
    And a new role with name "Class 1" and which is joined to the "Class 1" group to "Greenwich Steiner School" school
    And I am logged in as "example" organisation owner

  Scenario: Add new oauth client
    Given I follow "OAuth clients"
    And I follow "New"
    When I fill in "Name" with "Example software"
    And I fill in "Client id" with "fXLDE5FKas42DFgsfhRTfdli"
    And I fill in "Client secret" with "zK7oEm34gYk3hA54DKX8da4"
    And I fill in "Access" with "read:personalInfo"
#    And I check "False"
    And I press "Create"
    Then I should see "Example software"
