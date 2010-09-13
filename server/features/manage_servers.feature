Feature: Manage servers
  In order to [goal]
  [stakeholder]
  wants [behaviour]

  Background:
    Given I am logged in as "cucumber" with password "cucumber"


  Scenario: Register new server
    Given I am on the new server page
    When I fill in "Hostname" with "puavoHostname 1"
    And I fill in "Mac address" with "52:54:01:00:00:89"
    And I fill in "Serial number" with "123456789"
    And I select "Server" from "Device type"
    And I press "Create"
    Then I should see "puavoHostname 1"
    And I should see "52:54:01:00:00:89"
    And I should see "123456789"

  Scenario: Delete server
    Given the following servers:
      | puavoHostname   | macAddress   | serialNumber   | puavoDeviceType |
      | puavoHostname 1 | macAddress 1 | serialNumber 1 | server          |
      | puavoHostname 2 | macAddress 2 | serialNumber 2 | server          |
      | puavoHostname 3 | macAddress 3 | serialNumber 3 | server          |
      | puavoHostname 4 | macAddress 4 | serialNumber 4 | server          |
    When I delete the 3rd server
    Then I should see the following servers:
      |Hostname|
      |puavoHostname 1|
      |puavoHostname 2|
      |puavoHostname 4|
