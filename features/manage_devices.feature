Feature: Manage devices

  Background:
    Given a new school and group with names "Example school 1", "Class 1" on the "example" organisation
    And a new role with name "Student" and which is joined to the "Class 1" group
    And the following roles:
    | displayName |
    | Staff       |
    And the following users:
      | givenName | sn     | uid   | password | school_admin | role_name | puavoEduPersonAffiliation |
      | Pavel     | Taylor | pavel | secret   | true         | Staff     | staff                     |
    And I am logged in as "pavel" with password "secret"
    And the following devices:
      | puavoHostname | macAddress        | puavoDeviceType | puavoMountpoint                                                      |
      | fatclient-01  | 33:2d:2b:13:ce:a0 | fatclient       | { "fs":"nfs3", "path":"10.0.0.1/share", "mountpoint":"/home/share" } |
      | fatclient-02  | a0:4e:68:94:a1:7b | fatclient       | { "fs":"nfs3", "path":"10.0.0.1/share", "mountpoint":"/home/share" } |
      | laptop-01     | a0:4e:68:94:a1:7c | laptop          | { "fs":"nfs3", "path":"10.0.0.1/share", "mountpoint":"/home/share" } |

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
    And I fill in "device_fs_0" with "nfs3"
    And I fill in "device_path_0" with "10.0.0.1/share"
    And I fill in "device_mountpoint_0" with "/home/share"
    And I fill in "device_options_0" with "-o rw"
    And I select "13" from "device[puavoDeviceOnHour]"
    And I select "19" from "device[puavoDeviceOffHour]"
    And I choose "device_puavoDeviceAutoPowerOffMode_default"
    And I choose "device_puavoDeviceAutoPowerOffMode_off"
    And I choose "device_puavoDeviceAutoPowerOffMode_custom"
    And I press "Update"
    Then I should see "usb://input-audio-device"
    And I should see "usb://output-audio-device"
    And I should see "nfs3"
    And I should see "10.0.0.1/share"
    And I should see "/home/share"
    And I should see "-o rw"
    And I should see "Auto power off mode"
    And I should see "Auto power off mode"
    And I should see "Daytime start"
    And I should see "Daytime end"

  Scenario: Edit laptop configuration
    Given I am on the devices list page
    And I press "Edit" on the "laptop-01" row
    When I choose "device_puavoAutomaticImageUpdates_true"
    And I choose "device_puavoPersonallyAdministered_true"
    And I press "Update"
    Then I should see "Device was successfully updated."
    And I should see "Automatic image updates Yes"
    And I should see "Personally administered Yes"

  Scenario: Change primary user for laptop
    Given I am on the devices list page
    And I press "Edit" on the "laptop-01" row
    And I fill in "Device primary user" with "pavel"
    And I press "Update"
    Then I should see "Device was successfully updated."
    And I should see "Device primary user Pavel Taylor"
    When I follow "Edit"
    And I fill in "Device primary user" with ""
    And I press "Update"
    Then I should see "Device was successfully updated."
    And I should not see "Device primary user Pavel Taylor"
