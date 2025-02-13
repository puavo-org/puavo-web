Feature: Manage devices

  Background:
    Given a new school and group with names "Example school 1", "Class 1" on the "example" organisation
    And the following users:
      | givenName | sn     | uid        | password   | school_admin | puavoEduPersonAffiliation |
      | Pavel     | Taylor | pavel      | secret     | true         | admin                     |
      | Huey      | Duck   | huey       | password   | false        | student                   |
      | Super     | Admin  | superadmin | tXFwIFcJN9 | true         | admin                     |
      | Super     | Admin  | multiadmin | rWVpsiqjzG | true         | admin                     |
    And I am logged in as "example" organisation owner
    And admin "superadmin" has these permissions: "create_devices delete_devices device_change_school"
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
    And I fill in "Description" with "An example device"
    And I fill in "Notes" with "This is a fatclient used in this test"
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
    And I should see "An example device"
    And I should see "This is a fatclient used in this test"
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

  Scenario: Deleting the device primary user should not leave behind stale references to them
    # Setup
    Given I am on the devices list page
    And I press "Edit..." on the "laptop-01" row
    And I fill in "Device primary user" with "huey"
    And I press "Update"
    Then I should see "Device was successfully updated."
    And I should see "Device primary user Huey Duck"
    And the primary user of the device "laptop-01" should be "huey"
    # Delete (must login as "cucumber" to see the delete button)
    Given I am logged in as "cucumber" with password "cucumber"
    Given I am on the show user page with "huey"
    And I should see "Delete user"
    When I follow "Delete user"
    Then I should see "User was successfully removed."
    # Verify
    Given I am on the show device page with "laptop-01"
    Then I should not see "Huey Duck"
    And the primary user of the device "laptop-01" should be nil

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

  Scenario: .img extension is removed from desktop image names
    Given I am on the devices list page
    And I press "Edit..." on the "laptop-01" row
    And I fill in "Desktop Image" with "example_image.img"
    And I press "Update"
    # All "I should see" and "I should not see" checks are just simple
    # substring searches. If there's "example_image.img" on the page,
    # then it will match to "example_image". So we must check for the
    # absence of the extension itself.
    Then I should not see ".img"
    When I follow "Edit..."
    And I fill in "Desktop Image" with "example_image_2"
    And I press "Update"
    Then I should see "example_image_2"

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

  Scenario: Ensure display settings (XML) can be edited
    Given I am on the devices list page
    And I press "Edit..." on the "fatclient-01" row
    And I fill in "Display settings (XML)" with:
      """
      <monitors version="1">
	<configuration>
	  <clone>no</clone>
	  <output name="DP1">
	    ...
	  </output>
	</configuration>
      </monitors>
      """
    And I press "Update"
    Then I should see "Device was successfully updated."
    And I should see:
      """
      <monitors version="1"> <configuration> <clone>no</clone> <output name="DP1"> ... </output> </configuration> </monitors>
      """

  Scenario: Admins should not see the new device button unless device creation has been permitted
    Given I am logged in as "pavel" with password "secret"
    And I am on the devices list page
    Then I should not see "Add a new device"

  Scenario: Admins should not see device deletion buttons unless device deletion has been permitted
    Given I am logged in as "pavel" with password "secret"
    Then I am on the devices list page
    And I should not see "Remove"
    Then I follow "laptop-01"
    And I should see "laptop-01.example.puavo.net"
    And I should not see "Delete device"

  Scenario: Admins should see the new device button if device creation has been permitted
    Given I am logged in as "superadmin" with password "tXFwIFcJN9"
    And I am on the devices list page
    Then I should see "Add a new device"

  Scenario: Admins should see device deletion buttons if device deletion has been permitted
    Given I am logged in as "superadmin" with password "tXFwIFcJN9"
    Then I am on the devices list page
    And I should see "Remove"
    Then I follow "laptop-01"
    And I should see "laptop-01.example.puavo.net"
    And I should see "Delete device"

  Scenario: List admin permissions
    Given I am on the show user page with "superadmin"
    And I should see "can add and register new devices"
    And I should see "can delete devices"
    And I should not see "can mass delete multiple devices"

  # Test that owners can move a device to another school. This works because there is
  # another school (Administration) in the organisation during this test.
  Scenario: Quick device school changing test
    Given I am logged in as "cucumber" with password "cucumber"
    And I am on the change device school page with "laptop-01"
    Then I should see:
      """
      Move device "laptop-01" to another school
      """
    And I should see "Select the new school"
    When I press "Move device"
    Then I should see "Device moved to another school"
    And I should see "Administration" within "header#schoolName"

  Scenario: Admins should not see the "change school" entry in the menu if device school changing has not been permitted
    Given I am logged in as "pavel" with password "secret"
    And I am on the show device page with "laptop-01"
    Then I should not see "Change school..."

  Scenario: Admins cannot even navigate to the device school change page if device school changing has not been permitted
    Given I am logged in as "pavel" with password "secret"
    And I am on the change device school page with "laptop-01"
    Then I should see "You do not have enough rights to access that page."
    And I should not see:
      """
      Move device "laptop-01" to another school
      """

  Scenario: Ensure the device school change page is accessible when school changes are permitted
    Given I am logged in as "superadmin" with password "tXFwIFcJN9"
    And I am on the show device page with "laptop-01"
    Then I should see "Change school..."
    When I follow "Change school..."
    Then I should see "This organisation has no other schools where you could move this device to"

  # But there's one missing important test here: test that an admin actually can move
  # a device to another school. I cannot figure out how to (easily) create an admin that
  # is in multiple schools.
