Feature: Manage servers
  In order to [goal]
  [stakeholder]
  wants [behaviour]

  Background:
    Given a new school and group with names "Example school 1", "Class 1" on the "example" organisation
    And a new school and group with names "Example school 2", "Class 1" on the "example" organisation
    And the following servers:
    | puavoHostname | macAddress        |
    | someserver    | bc:5f:f4:56:59:71 |
    And I am logged in as "cucumber" with password "cucumber"

  Scenario: Add new group to school
    Given I am on the server list page
    Then I should see "someserver"
    And I follow "someserver"
    And I follow "Edit"
    And I check "Example school 2"
    And I press "Update"
    And I should see "This LTSP server will only serve these schools"
