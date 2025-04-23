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
    And I follow "Edit..."
    Then I fill in the following:
    | Description                                    | Example Organisation located  in the middle of the Finland |
    | OID                                            | 1.2.246.562.99.00000000001                                 |
    | Notes                                          | Just an example organisation. Nothing serious.             |
    | Phone number                                   | 123456789                                                  |
    | Fax number                                     | 987654321                                                  |
    | Locality                                       | Example locality                                           |
    | Street address                                 | Example stree 435                                          |
    | Post Office Box                                | 1001                                                       |
    | Postal address                                 | Example postal address                                     |
    | Postal code                                    | 88888                                                      |
    | State                                          | Keski-suomen lääni                                         |
    | Home page                                      | http://www.example.org                                     |
    | Name                                           | Example Organisation 2                                     |
    | Abbreviation                                   | jkl                                                        |
    | Keyboard layout                                | en                                                         |
    | Keyboard varian                                | US                                                         |
    | ldap_organisation[puavoImageSeriesSourceURL][] | http://foobar.puavo.net/trusty                             |
# FIXME: fix acl?
#    | ldap_organisation[puavoBillingInfo][] | base:500                                                   |
    And I fill in "PuavoConf settings" with:
      """
      {
        "puavo.desktop.vendor.logo": "/usr/share/puavo-art/puavo-os_logo-white.svg",
        "puavo.l10n.locale": "ja_JP.eucJP",
        "puavo.login.external.enabled": true,
        "puavo.time.timezone": "Europe/Tallinn"
      }
      """
    And I select "(GMT+02:00) Helsinki" from "Time zone"
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
    | Just an example organisation. Nothing serious.             |
    | 1.2.246.562.99.00000000001                                 |
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
    | http://foobar.puavo.net/trusty                             |
#    | base:500                                                   |
    And I should see the following special ldap attributes on the "Organisation" object with "example":
    | preferredLanguage | "sv" |
    And I should see the following puavo-conf values:
    | puavo.desktop.vendor.logo    | /usr/share/puavo-art/puavo-os_logo-white.svg |
    | puavo.l10n.locale            | ja_JP.eucJP                                  |
    | puavo.login.external.enabled | true                                         |
    | puavo.time.timezone          | Europe/Tallinn                               |

  Scenario: Add or remove organisation owner
    Given the following users:
    | givenName | sn     | uid   | password | puavoEduPersonAffiliation | school                   |
    | Pavel     | Taylor | pavel | secret   | admin                     | Greenwich Steiner School |
    When I follow "Owners"
    And I follow "Add" on the "Pavel Taylor" user
    Then I should see "Pavel Taylor is now an owner of this organisation"
    Given I am on the show user page with "pavel"
    Then I should see "The user is an owner of this organisation"
    When I follow "Owners"
    When I follow "Remove" on the "Pavel Taylor" user
    Then I should see "Pavel Taylor is no longer an owner of this organisation"
    Given I am on the show user page with "pavel"
    Then I should not see "The user is an owner of this organisation"

  Scenario: Removing a user actually removes them from the organisation owners
    Given the following users:
    | givenName | sn     | uid   | password | puavoEduPersonAffiliation | school                   |
    | Pavel     | Taylor | pavel | secret   | admin                     | Greenwich Steiner School |
    When I follow "Owners"
    And I follow "Add" on the "Pavel Taylor" user
    Then I should see "Pavel Taylor is now an owner of this organisation"
    Given I am on the show user page with "pavel"
    Then I should see "The user is an owner of this organisation"
    When I follow "Delete user"
    Then I should see "User was successfully removed."
    When I follow "Owners"
    Then I should not see "Pavel Taylor"


  Scenario: Try to set student to organisation owner
    Given the following users:
    | givenName | sn  | uid      | password | puavoEduPersonAffiliation | school                   |
    | Jane      | Doe | jane.doe | secret   | admin                     | Greenwich Steiner School |
    When I follow "Owners"
    And I change "jane.doe" user type to "student"
    And I follow "Add" on the "Jane Doe" user
    And I should see "Organisation owner access rights can be added only if the type of the user is admin"

  Scenario: Owners can't remove their own owner rights
    Given the following users:
    | givenName | sn   | uid    | password | puavoEduPersonAffiliation | school                   |
    | Donald    | Duck | donald | 313      | admin                     | Greenwich Steiner School |
    When I follow "Owners"
    And I follow "Add" on the "Donald Duck" user
    Then I should see "Donald Duck is now an owner of this organisation"
    Given I am logged in as "donald" with password "313"
    When I follow "Owners"
    Then I should see "(You can't remove your own owner-level rights)"

  Scenario: .img extension is removed from desktop image names
    When I follow "About"
    And I follow "Edit..."
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
