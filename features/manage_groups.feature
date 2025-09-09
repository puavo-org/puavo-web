Feature: Manage groups
  In order to [goal]
  [stakeholder]
  wants [behaviour]

  Background:
    Given a new school and group with names "Example school 1", "Class 1" on the "example" organisation
    And the following users:
      | givenName | sn     | uid     | password | school_admin | puavoEduPersonAffiliation |
      | Pavel     | Taylor | pavel   | secret   | true         | admin                     |
      | Another   | Admin  | another | secret2  | true         | admin                     |
      | Third     | Admin  | third   | secret3  | true         | admin                     |
    And admin "pavel" has these permissions: "create_groups delete_groups group_change_school"
    And admin "third" has these permissions: "create_groups"
    And I am logged in as "pavel" with password "secret"

  Scenario: Add new group to school
    Given I am on the new group page
    Then I should see "New group"
    When I fill in "Group name" with "Class 4A"
    And I fill in "Abbreviation" with "class4a"
    And I fill in "Notes" with "Just some random group used in this test"
    And I press "Create"
    Then I should see "Group was successfully created."
    And I should see "Class 4A"
    And I should see "Example school 1"
    And I should see "class4a"
    And I should see "Just some random group used in this test"
    When I follow "New group"
    Then I should be on the new group page

  Scenario: Add duplicate group to school
    Given the following groups:
    | displayName | cn      |
    | Class 4A    | class4a |
    And I am on the new group page
    When I fill in "Group name" with "Class 4A"
    And I fill in "Abbreviation" with "class4a"
    And I press "Create"
    #Then I should see "Group name has already been taken"
    And I should see "Abbreviation has already been taken"
    When I fill in "Abbreviation" with "exampleschool1"
    And I press "Create"
    Then I should see "Abbreviation has already been taken"

  Scenario: Add group with empty Group name and Abbreviation
    And I am on the new group page
    When I press "Create"
    Then I should see "Group name can't be blank"
    And I should see "Abbreviation can't be blank"
    And I should see "Failed to create group!"

  Scenario: Invalid characters in the group abbreviation
    And I am on the new group page
    When I fill in "Group name" with "Test"
    And I fill in "Abbreviation" with "test/"
    When I press "Create"
    And I should see "Abbreviation contains invalid characters (allowed characters are a-z0-9-)"
    And I should see "Failed to create group!"
    Then I fill in "Abbreviation" with "test."
    When I press "Create"
    And I should see "Abbreviation contains invalid characters (allowed characters are a-z0-9-)"
    Then I fill in "Abbreviation" with "test "
    When I press "Create"
    And I should see "Abbreviation contains invalid characters (allowed characters are a-z0-9-)"
    Then I fill in "Abbreviation" with "test"
    When I press "Create"
    And I should see "Group was successfully created."

  Scenario: Reserved group abbreviations
    Given I am on the new group page
    When I fill in "Group name" with "Test"
    And I fill in "Abbreviation" with "root"
    When I press "Create"
    Then I should see "This abbreviation is a reserved system group name"
    And I should see "Failed to create group!"
    When I fill in "Abbreviation" with "sudo"
    And I press "Create"
    Then I should see "This abbreviation is a reserved system group name"
    When I fill in "Abbreviation" with "puavo-os"
    And I press "Create"
    Then I should see "This abbreviation is a reserved system group name"
    When I fill in "Abbreviation" with "puavo"
    And I press "Create"
    Then I should see "This abbreviation is a reserved system group name"
    When I fill in "Abbreviation" with "lpadmin"
    And I press "Create"
    Then I should see "This abbreviation is a reserved system group name"

  Scenario: Edit group information
    Given the following groups:
    | displayName | cn      |
    | Class 4A    | class4a |
    | Class 6B    | class6b |
    And I am on the edit group page with "Class 4A"
    When I fill in "Group name" with "Class 5A"
    And I fill in "Abbreviation" with "class5a"
    And I press "Update"
    Then I should see "Class 5A"
    And I should see "class5a"
    And I should see "Example school 1"

  Scenario: Edit group and set empty values
    Given the following groups:
    | displayName | cn      |
    | Class 4A    | class4a |
    | Class 6B    | class6b |
    And I am on the edit group page with "Class 4A"
    When I fill in "Group name" with ""
    And I fill in "Abbreviation" with ""
    And I press "Update"
    Then I should see "Group name can't be blank"
    And I should see "Abbreviation can't be blank"
    And I should see "Group cannot be saved!"

  Scenario: Listing groups
    Given the following groups:
    | displayName | cn      |
    | Class 4A    | class4a |
    | Class 6B    | class6b |
    And I add user "pavel" to teaching group "Class 1"
    And I am on the groups list page
    Then I should see "Class 4A (0)"
    And I should see "Class 6B (0)"
    And I should see "Class 1 (1)"

  Scenario: Delete group
    Given the following groups:
    | displayName | cn      |
    | Class 4A    | class4a |
    And I am on the group page with "Class 4A"
    When I follow "Remove group"
    Then I should see "Group was successfully removed."

  Scenario: Check group special ldap attributes
    Given the following groups:
    | displayName | cn      |
    | Class 4A    | class4a |
    Then I should see the following special ldap attributes on the "Group" object with "Class 4A":
    | sambaSID       | "^S[-0-9+]" |
    | sambaGroupType | "2"         |

  Scenario: Add new group with invalid abbreviation
    Given I am on the new group page
    When I fill in "Group name" with "Class 4A"
    And I fill in "Abbreviation" with "Class4a"
    And I press "Create"
    Then I should see "Abbreviation contains invalid characters (allowed characters are a-z0-9-)"
    When I fill in "Abbreviation" with "class 4a"
    And I press "Create"
    Then I should see "Abbreviation contains invalid characters (allowed characters are a-z0-9-)"
    When I fill in "Abbreviation" with "class-4a"
    And I press "Create"
    Then I should see "Group was successfully created."
    And I should see "Class 4A"
    And I should see "Example school 1"
    And I should see "class-4a"

  Scenario: Get members of group
    Given the following groups:
    | displayName | cn      |
    | Class 4     | class4  |
    And the following users:
    | givenName | sn     | uid  | password | puavoEduPersonAffiliation | groups |
    | Joe       | Bloggs | joe  | secret   | student                   | class4 |
    | Jane      | Doe    | jane | secret   | student                   | class4 |
    When I get on the members group JSON page with "Class 4"
    Then I should see JSON '[{"user_type":"student", "name":"Joe Bloggs", "uid":"joe", "given_name":"Joe", "surname":"Bloggs"},{"name":"Jane Doe", "user_type":"student", "uid":"jane", "surname":"Doe", "given_name":"Jane"}]'

  Scenario: Admins should not see the "change school" entry in the menu if group school changing has not been permitted
    Given the following groups:
    | displayName | cn      |
    | Class 4A    | class4a |
    And I am logged in as "another" with password "secret2"
    And I am on the group page with "Class 4A"
    Then I should not see "Change schools"

  Scenario: Admins cannot even navigate to the group school change page if group school changing has not been permitted
    Given the following groups:
    | displayName | cn      |
    | Class 4A    | class4a |
    And I am logged in as "another" with password "secret2"
    And I am on the change group school page with "Class 4A"
    Then I should see "You do not have enough rights to access that page."

  Scenario: If group school changing is permitted, then the menu item is also visible
    Given the following groups:
    | displayName | cn      |
    | Class 4A    | class4a |
    And I am on the group page with "Class 4A"
    Then I should see "Change school..."

  # FIXME: This actually does test what it says in the title, because the admin has only one
  # school, so we can't even see the school changing form
  Scenario: Move group to another school (admin)
    Given I am on the new group page
    Then I should see "New group"
    When I fill in "Group name" with "Moving group"
    And I fill in "Abbreviation" with "moving"
    And I press "Create"
    Then I should see "Group was successfully created."
    When I follow "Change school..."
    Then I should see "This group cannot be moved to another school, because there are no other suitable schools"

  Scenario: Move group to another school (owner)
    Given the following schools:
    | displayName | cn      |
    | School 2    | school2 |

    Given I am logged in as "cucumber" with password "cucumber"
    And I am on the new group page
    Then I should see "New group"
    When I fill in "Group name" with "Moving group"
    And I fill in "Abbreviation" with "moving"
    And I press "Create"
    Then I should see "Group was successfully created."
    When I follow "Change school..."
    Then I should not see "This group cannot be moved to another school, because there are no other suitable schools"
    And I should not see "Example school 1" within "select#school"
    And I should see "School 2" within "select#school"
    When I select "School 2" from "school"
    And I press "Move"
    Then I should see:
      """
      Group moved to school "School 2"
      """

  Scenario: Can't create a new group if it hasn't been granted
    Given I am logged in as "another" with password "secret2"
    And I am on the new group page
    Then I should see "You do not have enough rights to access that page."

  Scenario: Can't see certain buttons
    Given I am logged in as "another" with password "secret2"
    And I am on the groups list page
    Then I should not see "New group..."
    And I should not see "Remove"
    Then I am on the group page with "Class 1"
    And I should not see "New group..."
    And I should not see "Remove group"

  Scenario: Can only see some buttons
    Given I am logged in as "third" with password "secret3"
    And I am on the groups list page
    Then I should see "New group..."
    And I should not see "Remove"
    Then I am on the group page with "Class 1"
    And I should see "New group..."
    And I should not see "Remove group"

  Scenario: Limited admin can create new groups
    Given I am logged in as "third" with password "secret3"
    And I am on the groups list page
    When I follow "New group..."
    Then I should not see "You do not have enough rights to access that page."
    # The following steps were copied from an earlier scenario
    When I fill in "Group name" with "Class 4A"
    And I fill in "Abbreviation" with "class4a"
    And I fill in "Notes" with "Just some random group used in this test"
    And I press "Create"
    Then I should see "Group was successfully created."
    And I should see "Class 4A"
    And I should see "Example school 1"
    And I should see "class4a"
    And I should see "Just some random group used in this test"
