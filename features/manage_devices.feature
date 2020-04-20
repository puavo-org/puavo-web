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
      | thin-01       | 11:22:33:aa:bb:cc | thinclient      | { "fs":"nfs3", "path":"10.0.0.1/share", "mountpoint":"/home/share" } |

  Scenario: Add new printer to Puavo
    Given I am on the new printer device page
    When I fill in "Hostname" with "testprinter01"
    And I press "Create"
    Then I should see "Device was successfully created."

  Scenario: Edit fatclient configuration
    Given I am on the devices list page
    And I press "Edit..." on the "fatclient-01" row
    When I fill in "Default input audio device" with "usb://input-audio-device"
    And I fill in "Default output audio device" with "usb://output-audio-device"
    And I fill in "device_fs_0" with "nfs3"
    And I fill in "device_path_0" with "10.0.0.1/share"
    And I fill in "device_mountpoint_0" with "/home/share"
    And I fill in "device_options_0" with "-o rw"
    And I fill in "PuavoConf settings" with:
      """
      {
        "puavo.autopilot.enabled": false,
        "puavo.guestlogin.enabled": false,
        "puavo.xbacklight.brightness": 55
      }
      """
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
    And I should see the following puavo-conf values:
    | puavo.autopilot.enabled     | false |
    | puavo.guestlogin.enabled    | false |
    | puavo.xbacklight.brightness | 55    |

  Scenario: Edit laptop configuration
    Given I am on the devices list page
    And I press "Edit..." on the "laptop-01" row
    When I choose "device_puavoAutomaticImageUpdates_true"
    And I choose "device_puavoPersonallyAdministered_true"
    And I press "Update"
    Then I should see "Device was successfully updated."
    And I should see "Automatic image updates Yes"
    And I should see "Personally administered Yes"

  Scenario: Change primary user for laptop
    Given I am on the devices list page
    And I press "Edit..." on the "laptop-01" row
    And I fill in "Device primary user" with "pavel"
    And I press "Update"
    Then I should see "Device was successfully updated."
    And I should see "Device primary user Pavel Taylor"
    When I follow "Edit..."
    And I fill in "Device primary user" with ""
    And I press "Update"
    Then I should see "Device was successfully updated."
    And I should not see "Device primary user Pavel Taylor"

  Scenario: Change Image series source URL
    Given I am logged in as "example" organisation owner
    And I am on the devices list page
    And I press "Edit..." on the "laptop-01" row
    And I fill in "device[puavoImageSeriesSourceURL][]" with "http://foobar.puavo.net/buster"
    And I press "Update"
    And I should see "http://foobar.puavo.net/buster"

  Scenario: Check for unique tags
    Given I am on the devices list page
    And I press "Edit..." on the "laptop-01" row
    And I fill in "Tags" with "tagA tagB"
    And I press "Update"
    Then I should see "Device was successfully updated."
    And I should see "tagA tagB"

  Scenario: Check that duplicate tags are removed
    Given I am on the devices list page
    And I press "Edit..." on the "laptop-01" row
    And I fill in "Tags" with "tagA tagB tagB"
    And I press "Update"
    Then I should see "Device was successfully updated."
    And I should see "tagA tagB"

  Scenario: Give the device an image
    Given I am on the devices list page
    And I press "Edit..." on the "laptop-01" row
    And I attach the file at "features/support/test.jpg" to "Image"
    And I press "Update"
    Then I should see "Device was successfully updated."

  Scenario: Give the device a non-image file as the image
    Given I am on the devices list page
    And I press "Edit..." on the "laptop-01" row
    And I attach the file at "features/support/hello.txt" to "Image"
    And I press "Update"
    Then I should see "Failed to save the image"

  Scenario: Ensure invalid characters in the serial number field don't crash (part 1)
    Given I am on the devices list page
    And I press "Edit..." on the "fatclient-01" row
    And I fill in "Serial number" with "ääääää"
    And I press "Update"
    Then I should see "Serial number contains invalid characters"

  Scenario: Ensure invalid characters in the serial number field don't crash (part 2)
    Given I am on the devices list page
    And I press "Edit..." on the "thin-01" row
    And I fill in "Serial number" with "ääääää"
    And I press "Update"
    Then I should see "Serial number contains invalid characters"

  Scenario: Invalid primary user should not crash
    Given I am on the devices list page
    And I press "Edit..." on the "thin-01" row
    And I fill in "Device primary user" with "does not exist"
    And I press "Update"
    Then I should see "Device primary user is invalid"

  Scenario: Poor man's script injection check
    Given I am on the devices list page
    And I press "Edit..." on the "thin-01" row
    And I fill in "Device manufacturer" with "<script>alert(456)</script>"
    And I press "Update"
    Then I should see "Device was successfully updated"
    And I should see "<script>alert(456)</script>"

  Scenario: Ensure Markdown and HTML stays escaped and uninterpreted
    Given I am on the devices list page
    And I press "Edit..." on the "thin-01" row
    And I fill in "Description" with:
        """
        <h1>TITLE</h1> <a href="#">foobar</a> <ul><li>foo</li><li>bar</li></ul>
        # Header 1
        ## Header 2
        <img src="https://opinsys.fi/wp-content/uploads/2016/10/opinsys-logo.png"> _Markdown_ **is not always** cool. <script>alert(123)</script>
        """
    And I press "Update"
    Then I should see "Device was successfully updated."
    And I should see:
        """
        <h1>TITLE</h1> <a href="#">foobar</a> <ul><li>foo</li><li>bar</li></ul> # Header 1 ## Header 2 <img src="https://opinsys.fi/wp-content/uploads/2016/10/opinsys-logo.png"> _Markdown_ **is not always** cool. <script>alert(123)</script>
        """

  Scenario: Empty new device page should not cause crashes
    Given I am on the new other device page
    And I press "Create"
    Then I should see "Hostname can't be blank"

  Scenario: Device page of a non-existent school
    Given I am on the device page of a non-existent school
    Then I should see "The school ID is not valid."
