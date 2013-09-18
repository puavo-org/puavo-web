Feature: Manage printer permissions
  In order to [goal]
  [stakeholder]
  wants [behaviour]

  Background:
    Given a new school and group with names "Example school 1", "Class 1" on the "example" organisation
    And the following roles:
      | displayName |
      | Staff       |
    And the following users:
      | givenName | sn     | uid   | password | school_admin | role_name | puavoEduPersonAffiliation |
      | Pavel     | Taylor | pavel | secret   | true         | Staff     | Staff                     |
    And the following devices:
      | puavoHostname | macAddress        | puavoDeviceType |
      | athin         | 33:2d:2b:13:ce:a0 | thinclient      |
      | anotherthin   | a0:4e:68:94:a1:7b | thinclient      |
    And the following bootserver:
      | puavoHostname | macAddress        |
      | boot1         | 27:b0:59:3c:ac:a4 |
    And the following printers:
      | printerDescription | printerLocation | printerMakeAndModel  | printerType | printerURI   |
      | printer1           | a school        | foo                  | 1234        | socket://baz |
      | printer2           | a home          | foo                  | 1234        | socket://baz |

  Scenario: Can navigate to printer permissions list
    Given I am logged in as "pavel" with password "secret"
    And I am on the show school page with "Example school 1"
    When I follow "Devices"
    And I follow "Printer Queues"
    Then I should see "Available printers"
    Then I should see "printer1"
    Then I should see "Edit permissions"

  Scenario: Can activate printer for school
    Given I am logged in as "pavel" with password "secret"
    And I am on the printer permissions page
    And I should see "Available printers"
    And I press "Edit permissions" on the "printer1" row
    Then I should see "Printer usage permissions"
    Then I should see "printer1"
