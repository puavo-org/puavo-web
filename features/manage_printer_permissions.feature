Feature: Manage printer permissions
  In order to [goal]
  [stakeholder]
  wants [behaviour]

  Background:
    Given the following schools:
    | displayName   | cn          | puavoAllowGuest | puavoPersonalDevice |
    | Test School 1 | testschool1 | false           | true                |
    And a new school and group with names "Example school 1", "Class 1" on the "example" organisation
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
      | puavoHostname | macAddress        | school           |
      | boot1         | 27:b0:59:3c:ac:a4 | Example school 1 |
      | boot2         | 27:b0:59:3c:ac:a5 | Test School 1    |
    And the following printers for "boot1" bootserver:
      | printerDescription | printerLocation | printerMakeAndModel  | printerType | printerURI   |
      | printer1           | a school        | foo                  | 1234        | socket://baz |
      | printer2           | a home          | foo                  | 1234        | socket://baz |
    And the following printers for "boot2" bootserver:
      | printerDescription | printerLocation | printerMakeAndModel  | printerType | printerURI   |
      | printer3           | a school        | foo                  | 1234        | socket://baz |
      | printer4           | a home          | foo                  | 1234        | socket://baz |

  Scenario: Can navigate to printer permissions list
    Given I am logged in as "pavel" with password "secret"
    And I am on the show school page with "Example school 1"
    When I follow "Devices"
    And I follow "Printing permissions"
    Then I should see "printer1"
    Then I should see "Edit permissions"
    And I should not see "printer3"

  Scenario: Can activate printer for school
    Given I am logged in as "pavel" with password "secret"
    And I am on the printer permissions page
    And I press "Edit permissions" on the "printer1" row
    Then I should see "Printer usage permissions"
    And I should see "printer1"
    And I choose "Printing allowed on the all system devices"
    And I press "Save"
    Then the "Printing allowed on the all system devices" checkbox should be checked
    Then the "Printing allowed on the all system devices and also other devices (eg. tablets, phones, etc.)" checkbox should not be checked
    And the "Advanced" checkbox should not be checked
    And allow guest is disable in the "Example school 1" school
    And personal device is enable in the "Example school 1" school

  Scenario: Can activate wireless printer for school
    Given I am logged in as "pavel" with password "secret"
    And I am on the printer permissions page
    And I press "Edit permissions" on the "printer1" row
    And I choose "Printing allowed on the all system devices and also other devices (eg. tablets, phones, etc.)"
    And I press "Save"
    Then the "Printing allowed on the all system devices and also other devices (eg. tablets, phones, etc.)" checkbox should be checked
    Then the "Printing allowed on the all system devices" checkbox should not be checked

  Scenario: Can activate printer for group
    Given I am logged in as "pavel" with password "secret"
    And I am on the printer permissions page
    And I press "Edit permissions" on the "printer1" row
    And I check "Class 1"
    And I press "Save"
    Then the "Class 1" checkbox should be checked

  Scenario: Can activate printer from device
    Given I am logged in as "pavel" with password "secret"
    And I am on the edit page of "athin" device
    And I should see "Terminal information"
    And I check "printer1"
    And I press "Update"
    And I follow "Edit"
    Then the "printer1" checkbox should be checked
    And I press "printer1" on the "printer1" list
    And I should see "athin"
    # the remove checkbox
    Then I check box on the "athin" row
    And I press "Save"
    Then I should not see "athin"

