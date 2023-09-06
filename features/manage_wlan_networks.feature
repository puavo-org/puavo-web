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
    And I check "wlan_ap[0]"
    And I press "Update"
    And I should see "WLAN settings successfully updated"
    Then I should see the following JSON on the "Organisation" object with "example" on attribute "wlan_networks":
      """
        [
          { "ssid": "Open_test_network", "type": "open", "priority": "", "wlan_ap": true }
        ]
      """

  Scenario: Create a wpa-psk protected network
    Given I follow "Wireless networks"
    When I select "PSK" from "wlan_type[0]"
    And I fill in the following:
    | wlan_name[0]     | WPA_PSK_test_network   |
    | wlan_password[0] | HessuHoponHauskutukset |
    And I check "wlan_ap[0]"
    And I press "Update"
    And I should see "WLAN settings successfully updated"
    Then I should see the following JSON on the "Organisation" object with "example" on attribute "wlan_networks":
      """
        [
          {
            "ssid": "WPA_PSK_test_network",
            "type": "psk",
            "priority": "",
            "wlan_ap": true,
            "password": "HessuHoponHauskutukset"
          }
        ]
      """

  Scenario: Create two networks, other not AP-enabled
    Given I follow "Wireless networks"
    When I select "Open" from "wlan_type[0]"
    When I select "PSK" from "wlan_type[1]"
    And I fill in the following:
    | wlan_name[0]     | OpenNetworkNoAP       |
    | wlan_name[1]     | WPANetworkYesAP       |
    | wlan_password[1] | TipiLinnunTaikatemput |
    And I check "wlan_ap[1]"
    And I press "Update"
    And I should see "WLAN settings successfully updated"
    Then I should see the following JSON on the "Organisation" object with "example" on attribute "wlan_networks":
      """
        [
          { "ssid": "OpenNetworkNoAP", "type": "open", "priority": "", "wlan_ap": false },
          {
            "ssid": "WPANetworkYesAP",
            "type": "psk",
            "priority": "",
            "wlan_ap": true,
            "password": "TipiLinnunTaikatemput"
          }
        ]
      """

  Scenario: Create an open network and change it to WPA-protected
    Given I follow "Wireless networks"
    When I select "Open" from "wlan_type[0]"
    And I fill in the following:
    | wlan_name[0] | MyOwnNetwork |
    And I press "Update"
    And I should see "WLAN settings successfully updated"
    Then I should see the following JSON on the "Organisation" object with "example" on attribute "wlan_networks":
      """
        [
          {
            "ssid": "MyOwnNetwork",
            "type": "open",
            "priority": "",
            "wlan_ap": false
          }
        ]
      """
    And I am logged in as "example" organisation owner
    And I follow "Wireless networks"
    And I select "PSK" from "wlan_type[0]"
    And I fill in the following:
    | wlan_password[0] | AllYouNeedIsLove |
    And I check "wlan_ap[0]"
    And I press "Update"
    And I should see "WLAN settings successfully updated"
    Then I should see the following JSON on the "Organisation" object with "example" on attribute "wlan_networks":
      """
        [
          {
            "ssid": "MyOwnNetwork",
            "password": "AllYouNeedIsLove",
            "type": "psk",
            "priority": "",
            "wlan_ap": true
          }
        ]
      """

  Scenario: Changing WPA-protected network to open should lose password
    Given I follow "Wireless networks"
    When I select "PSK" from "wlan_type[0]"
    And I fill in the following:
    | wlan_name[0]     | MyOwnNetwork |
    | wlan_password[0] | SkiesAreBlue |
    And I press "Update"
    And I should see "WLAN settings successfully updated"
    Then I should see the following JSON on the "Organisation" object with "example" on attribute "wlan_networks":
      """
        [
          {
            "ssid": "MyOwnNetwork",
            "password": "SkiesAreBlue",
            "type": "psk",
            "priority": "",
            "wlan_ap": false
          }
        ]
      """
    And I am logged in as "example" organisation owner
    And I follow "Wireless networks"
    And I select "Open" from "wlan_type[0]"
    And I press "Update"
    And I should see "WLAN settings successfully updated"
    Then I should see the following JSON on the "Organisation" object with "example" on attribute "wlan_networks":
      """
        [
          {
            "ssid": "MyOwnNetwork",
            "type": "open",
            "priority": "",
            "wlan_ap": false
          }
        ]
      """

  Scenario: Create a new EAP-TLS network
    Given I follow "Wireless networks"
    When I select "EAP-TLS" from "wlan_type[0]"
    And I fill in the following:
    | wlan_name[0] | EAP-TLS_test_network |
    | wlan_client_key_password[0] | AnotherSecretOfMine |
    | wlan_identity[0] | Puavo |
    And I attach the file at "features/support/wlan_eaptls_ca_cert.txt" to "wlan_ca_cert[0]"
    And I attach the file at "features/support/wlan_eaptls_client_cert.txt" to "wlan_client_cert[0]"
    And I attach the file at "features/support/wlan_eaptls_client_key.txt" to "wlan_client_key[0]"
    And I press "Update"
    And I should see "WLAN settings successfully updated"
    Then I should see the following JSON on the "Organisation" object with "example" on attribute "wlan_networks":
      """
        [
          {
            "ssid": "EAP-TLS_test_network",
            "type": "eap-tls",
            "priority": "",
            "wlan_ap": false,
            "identity": "Puavo",
            "certs": {
              "ca_cert": "VGhpcyBmaWxlIGlzIG5vdCBhIHJlYWwgY2EtY2VydGlmaWNhdGUsIGJ1dCBh\nIGZha2Ugb25lLgo=\n",
              "client_cert": "VGhpcyBmaWxlIGlzIG5vdCBhIHJlYWwgY2xpZW50LWNlcnRpZmljYXRlLCBi\ndXQgYSBmYWtlIG9uZS4K\n",
              "client_key": "VGhpcyBmaWxlIGlzIG5vdCBhIHJlYWwgY2xpZW50LWtleSwgYnV0IGEgZmFr\nZSBvbmUuCg==\n",
              "client_key_password": "AnotherSecretOfMine"
            }
          }
        ]
      """

  Scenario: Check that EAP-TLS network ignores attributes not relevant
    Given I follow "Wireless networks"
    When I select "EAP-TLS" from "wlan_type[0]"
    And I fill in the following:
    | wlan_name[0]     | EAP-TLS_test_network |
    | wlan_password[0] | playblackholesun     |
    | wlan_identity[0] | Mulperi              |
    And I check "wlan_ap[0]"
    And I press "Update"
    And I should see "WLAN settings successfully updated"
    Then I should see the following JSON on the "Organisation" object with "example" on attribute "wlan_networks":
      """
        [
          {
            "ssid": "EAP-TLS_test_network",
            "type": "eap-tls",
            "priority": "",
            "wlan_ap": false,
            "identity": "Mulperi",
            "password": "playblackholesun"
          }
        ]
      """

  Scenario: Create a new EAP-TTLS network with no certificates
    Given I follow "Wireless networks"
    When I select "EAP-TTLS" from "wlan_type[0]"
    And I fill in the following:
    | wlan_name[0] | EAP-TTLS_test_network |
    | wlan_password[0] | justgetveracrypt |
    | wlan_identity[0] | Hillhouse |
    And I check "wlan_phase2_auth[0]"
    And I press "Update"
    And I should see "WLAN settings successfully updated"
    Then I should see the following JSON on the "Organisation" object with "example" on attribute "wlan_networks":
      """
        [
          {
            "ssid": "EAP-TTLS_test_network",
            "type": "eap-ttls",
            "priority": "",
            "wlan_ap": false,
            "identity": "Hillhouse",
            "password": "justgetveracrypt",
            "phase2_auth": "mschapv2"
          }
        ]
      """

  Scenario: Create some wlan networks through the school interface
    Given I am on the show school page with "Example school 1"
    When I follow "WLAN"
    When I select "Open" from "wlan_type[0]"
    When I select "PSK" from "wlan_type[1]"
    When I select "EAP-TLS" from "wlan_type[2]"
    And I fill in the following:
    | wlan_name[0]                | OpenNetworkYesAP                  |
    | wlan_name[1]                | WPANetworkNoAP                    |
    | wlan_name[2]                | EAPTLSNetwork                     |
    | wlan_password[1]            | SpoonmanComeTogetherWithYourHands |
    | wlan_client_key_password[2] | GetRightWithMe                    |
    | wlan_identity[2]            | EAPTLSNetworkIdentity             |
    And I check "wlan_ap[0]"
    And I attach the file at "features/support/wlan_eaptls_ca_cert.txt" to "wlan_ca_cert[2]"
    And I attach the file at "features/support/wlan_eaptls_client_cert.txt" to "wlan_client_cert[2]"
    And I attach the file at "features/support/wlan_eaptls_client_key.txt" to "wlan_client_key[2]"
    And I press "Update"
    And I should see "WLAN settings successfully updated"
    Then I should see the following JSON on the "Organisation" object with "example" on attribute "wlan_networks":
      """
        []
      """
    And I should see the following JSON on the "School" object with "Example school 1" on attribute "wlan_networks":
      """
        [
          { "ssid": "OpenNetworkYesAP", "type": "open", "priority": "", "wlan_ap": true },
          {
            "ssid": "WPANetworkNoAP",
            "type": "psk",
            "priority": "",
            "wlan_ap": false,
            "password": "SpoonmanComeTogetherWithYourHands"
          },
          {
            "ssid": "EAPTLSNetwork",
            "type": "eap-tls",
            "priority": "",
            "wlan_ap": false,
            "identity": "EAPTLSNetworkIdentity",
            "certs": {
              "ca_cert": "VGhpcyBmaWxlIGlzIG5vdCBhIHJlYWwgY2EtY2VydGlmaWNhdGUsIGJ1dCBh\nIGZha2Ugb25lLgo=\n",
              "client_cert": "VGhpcyBmaWxlIGlzIG5vdCBhIHJlYWwgY2xpZW50LWNlcnRpZmljYXRlLCBi\ndXQgYSBmYWtlIG9uZS4K\n",
              "client_key": "VGhpcyBmaWxlIGlzIG5vdCBhIHJlYWwgY2xpZW50LWtleSwgYnV0IGEgZmFr\nZSBvbmUuCg==\n",
              "client_key_password": "GetRightWithMe"
            }
          }
        ]
      """
