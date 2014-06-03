Feature: Manage organisation
  In order to [goal]
  [stakeholder]
  wants [behaviour]

  Background:
    Given a new school and group with names "Example school 1", "Class 1" on the "example" organisation
    And the following schools:
    | displayName              | cn        |
    | Greenwich Steiner School | greenwich |
    And a new role with name "Class 1" and which is joined to the "Class 1" group to "Greenwich Steiner School" school
    And I am logged in as "example" organisation owner

  Scenario: Show information of the organisation
    When I follow "About"
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
    When I follow "About"
    And I follow "Edit"
    Then I fill in the following:
    | Description                      | Example Organisation located  in the middle of the Finland |
    | Phone number                     | 123456789                                                  |
    | Fax number                       | 987654321                                                  |
    | Locality                         | Example locality                                           |
    | Street address                   | Example stree 435                                          |
    | Post Office Box                  | 1001                                                       |
    | Postal address                   | Example postal address                                     |
    | Postal code                      | 88888                                                      |
    | State                            | Keski-suomen lääni                                         |
    | Home page                        | http://www.example.org                                     |
    | Name                             | Example Organisation 2                                     |
    | Abbreviation                     | jkl                                                        |
# FIXME: fix acl?
#    | ldap_organisation[puavoBillingInfo][] | base:500                                                   |
    And I select "English (United States)" from "Preferred language"
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
    | English (United States)                                    |
    | 13                                                         |
    | 19                                                         |
    | Custom                                                     |
    | Example Organisation 2                                     |
    | jkl                                                        |
#    | base:500                                                   |
