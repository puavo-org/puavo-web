Feature: Manage groups
  In order to [goal]
  [stakeholder]
  wants [behaviour]

  Background:
    Given a new school and group with names "Example school 1", "Class 1" on the "example" organisation
    And the following users:
      | givenName | sn     | uid   | password | school_admin | puavoEduPersonAffiliation |
      | Pavel     | Taylor | pavel | secret   | true         | staff                     |
    And I am logged in as "pavel" with password "secret"

  Scenario: Add new group to school
    Given I am on the new group page
    Then I should see "New group"
    When I fill in "Group name" with "Class 4A"
    And I fill in "Abbreviation" with "class4a"
    And I press "Create"
    Then I should see "Group was successfully created."
    And I should see "Class 4A"
    And I should see "Example school 1"
    And I should see "class4a"
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
    Then I should see JSON '[{"user_type":"student", "name":"Joe Bloggs", "uid":"joe", "given_name":"Joe", "surname":"Bloggs", "reverse_name":"Bloggs Joe"},{"name":"Jane Doe", "user_type":"student", "uid":"jane", "surname":"Doe", "reverse_name":"Doe Jane", "given_name":"Jane"}]'

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
