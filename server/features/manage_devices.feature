Feature: Manage devices
  In order to [goal]
  [stakeholder]
  wants [behaviour]

  Background:
    Given I am logged in as "cucumber" with password "cucumber"
    And I am on the devices page with "Administration" school
  
  Scenario: Add new printer
    Given I follow "Add new printer"
    Then I should see "New printer"
    And I should see "Device type: Printer"
    When I fill in "Hostname" with "printer1"
    And I fill in "MAC address(es)" with "11:54:01:22:00:b7"
    And I press "Create"
    Then I should see "printer1"
    And I should see "11:54:01:22:00:b7"
