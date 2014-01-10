Feature: Manage devices

  Background:
    Given a new school and group with names "Example school 1", "Class 1" on the "example" organisation
    And a new role with name "Student" and which is joined to the "Class 1" group
    And the following roles:
    | displayName |
    | Staff       |
    And the following users:
      | givenName | sn     | uid   | password | school_admin | role_name | puavoEduPersonAffiliation |
      | Pavel     | Taylor | pavel | secret   | true         | Staff     | Staff                     |
    And I am logged in as "pavel" with password "secret"
    And the following devices:
      | puavoHostname | macAddress        | puavoDeviceType |
      | fatclient-01  | 33:2d:2b:13:ce:a0 | fatclient       |
      | fatclient-02  | a0:4e:68:94:a1:7b | fatclient       |

  Scenario: Add new printer to Puavo
    Given I am on the new printer device page
    When I fill in "Hostname" with "testprinter01"
    And I press "Create"
    Then I should see "Device was successfully created."

  Scenario: Edit fatclient configuration
    Given I am on the devices list page
    And I press "Edit" on the "fatclient-01" row
    When I fill in "Default input audio device" with "usb://input-audio-device"
    And I fill in "Default output audio device" with "usb://output-audio-device"
    And I press "Update"
    Then I should see "usb://input-audio-device"
    And I should see "usb://output-audio-device"
