Feature: Manage organisation
  In order to [goal]
  [stakeholder]
  wants [behaviour]

  Background:
    Given a new school and group with names "Example school 1", "Class 1" on the "example" organisation
    And the following schools:
    | displayName              | cn        |
    | Greenwich Steiner School | greenwich |
    And the following groups:
    | displayName | cn      |
    | Teacher     | teacher |
    And a new role with name "Class 1" and which is joined to the "Class 1" group to "Greenwich Steiner School" school
    And a new role with name "Teacher" and which is joined to the "Teacher" group to "Greenwich Steiner School" school
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
    | Description             | Example Organisation located  in the middle of the Finland |
    | Phone number            | 123456789                                                  |
    | Fax number              | 987654321                                                  |
    | Locality                | Example locality                                           |
    | Street address          | Example stree 435                                          |
    | Post Office Box         | 1001                                                       |
    | Postal address          | Example postal address                                     |
    | Postal code             | 88888                                                      |
    | State                   | Keski-suomen lääni                                         |
    | Home page               | http://www.example.org                                     |
    | Name                    | Example Organisation 2                                     |
    | Abbreviation            | jkl                                                        |
    | Keyboard layout         | en                                                         |
    | Keyboard varian         | US                                                         |
    | Image series source URL | http://foobar.opinsys.fi/trusty                            |
# FIXME: fix acl?
#    | ldap_organisation[puavoBillingInfo][] | base:500                                                   |
    And I select "(GMT+02:00) Helsinki" from "Timezone"
    And I select "Swedish (Finland)" from "Preferred language"
    And I select "13" from "ldap_organisation[puavoDeviceOnHour]"
    And I select "19" from "ldap_organisation[puavoDeviceOffHour]"
    And I choose "ldap_organisation_puavoDeviceAutoPowerOffMode_default"
    And I choose "ldap_organisation_puavoDeviceAutoPowerOffMode_off"
    And I choose "ldap_organisation_puavoDeviceAutoPowerOffMode_custom"
    And I choose "ldap_organisation_puavoAutomaticImageUpdates_true"
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
    | Swedish (Finland)                                          |
    | 13                                                         |
    | 19                                                         |
    | Custom                                                     |
    | Example Organisation 2                                     |
    | jkl                                                        |
    | (GMT+02:00) Helsinki                                       |
    | en                                                         |
    | US                                                         |
    | Automatic image updates Yes                                |
    | http://foobar.opinsys.fi/trusty                            |
#    | base:500                                                   |
    And I should see the following special ldap attributes on the "Organisation" object with "example":
    | preferredLanguage | "sv" |


  Scenario: Add or remove organisation owner
    Given the following users:
    | givenName | sn     | uid   | password | role_name | puavoEduPersonAffiliation | school                   |
    | Pavel     | Taylor | pavel | secret   | Teacher   | admin                     | Greenwich Steiner School |
    When I follow "Owners"
    And I follow "Add" on the "Pavel Taylor" user
    Then I should see "Pavel Taylor is now organisation owner"
    When I follow "Remove" on the "Pavel Taylor" user
    Then I should see "Pavel Taylor is no longer owner on this organisation"

  Scenario: Try to set student to organisation owner
    Given the following users:
    | givenName | sn  | uid      | password | role_name | puavoEduPersonAffiliation | school                   |
    | Jane      | Doe | jane.doe | secret   | Class 1   | admin                     | Greenwich Steiner School |
    When I follow "Owners"
    And I change "jane.doe" user type to "student"
    And I follow "Add" on the "Jane Doe" user
    And I should see "Organisation owner access rights can be added only if type of user is admin"

