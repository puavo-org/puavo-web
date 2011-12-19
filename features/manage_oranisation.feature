Feature: Manage organisation
  In order to [goal]
  [stakeholder]
  wants [behaviour]

  Background:
    Given the following schools:
    | displayName              | cn        |
    | Greenwich Steiner School | greenwich |
    And I am logged in as "example" organisation owner

  Scenario: Show information of the organisation
    When I follow "Example Organisation"
    Then I should see the following:
    | Example Organisation |
    | Description          |
    | Phone number         |
    | Fax number           |
    | Locality             |
    | Street address       |
    | Post Office Box      |
    | Postal address       |
    | Postal code          |
    | State                |
    | Preferred language   |
    | Home page            |
    | Auto power off mode  |
    | Daytime start        |
    | Daytime end          |

  Scenario: Edit information of the organisation
    When I follow "Example Organisation"
    And I follow "Edit"
    Then I fill in the following:
    | Description         | Example Organisation located  in the middle of the Finland |
    | Phone number        | 123456789                                                  |
    | Fax number          | 987654321                                                  |
    | Locality            | Example locality                                           |
    | Street address      | Example stree 435                                          |
    | Post Office Box     | 1001                                                       |
    | Postal address      | Example postal address                                     |
    | Postal code         | 88888                                                      |
    | State               | Keski-suomen lääni                                         |
    | Home page           | http://www.example.org                                     |
    And I select "English" from "ldap_organisation[preferredLanguage]"
    And I select "13" from "ldap_organisation[puavoDeviceOnHour]"
    And I select "19" from "ldap_organisation[puavoDeviceOffHour]"
    And I choose "ldap_organisation_puavoDeviceAutoPowerOffMode_default"
    And I choose "ldap_organisation_puavoDeviceAutoPowerOffMode_off"
    And I choose "ldap_organisation_puavoDeviceAutoPowerOffMode_custom"
    When I press "Update"
    Then I should see the following:
    | Example Organisation located  in the middle of the Finland |
    | 123456789                                                  |
    | 987654321                                                  |
    | Example locality                                           |
    | Example stree 435                                          |
    | 1001                                                       |
    | Example postal address                                     |
    | 88888                                                      |
    | Keski-suomen lääni                                         |
    | http://www.example.org                                     |
    | English                                                    |
    | 13                                                         |
    | 19                                                         |
    | Custom                                                     |
