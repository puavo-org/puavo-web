Feature: Manage wlan networks
  Managing wlan networks as an organisation owner

  Background:
    Given a new school and group with names "Example school 1", "Class 1" on the "example" organisation
    And I am logged in as "example" organisation owner

  Scenario: Create a new open network
    Given I follow "Wireless networks"
    When I select "Open" from "wlan_type[0]"
    And I fill in the following:
    | wlan_name[0] | Open_test_network |
    And I press "Update"
    And I should see "WLAN settings successfully updated"
    And I get the organisation JSON page with "cucumber" and "cucumber"
    Then I should see the following JSON on the "Organisation" object with "example" on attribute "wlan_networks":
      """
        [
	  { "ssid": "Open_test_network", "type": "open", "wlan_ap": true  },
	  { "ssid": "3rdpartywlan",      "type": "open", "wlan_ap": false },
	  { "ssid": "schoolwlan",        "type": "open", "wlan_ap": true  }
	]
      """
