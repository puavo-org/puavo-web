Feature: Manage groups
  In order to [goal]
  [stakeholder]
  wants [behaviour]

  Background:
    Given a new school and group with names "Example school 1", "Class 1" on the "example" organisation
    And a new role with name "Student" and which is joined to the "Class 1" group
    And the following roles:
    | displayName |
    | Staff       |
    And the following users:
      | givenName | sn     | uid   | password | school_admin | role_name | puavoEduPersonAffiliation |
      | Pavel     | Taylor | pavel | secret   | true         | Staff     | Staff                     |
    And I am logged in as "pavel" with password "secret"
  
  Scenario: Add new group to school
    Given I am on the new group page
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

  Scenario: Add role to the group
    Given the following groups:
    | displayName | cn      |
    | Class 4A    | class4a |
    | Class 6B    | class6b |
    And the following roles:
    | displayName |
    | Teacher |
    And I am set the "Teacher" role for "pavel"
    And I am on the group page with "Class 4A"
    Then I should see "Student (Example school 1)" on the "Other roles"
    And I should see "Teacher (Example school 1)" on the "Other roles"
    And I should not see "Pavel Taylor" on the "Roles and members"
    And the memberUid should not include "pavel" on the "Class 4A" group
    When I follow "Add" on the "Teacher" role
    Then I should see "Teacher (Example school 1)" on the "Roles and members"
    And I should not see "Teacher" on the "Other roles"
    And I should see "Student (Example school 1)" on the "Other roles"
    And I should see "Pavel Taylor" on the "Roles and members"
    And the memberUid should include "pavel" on the "Class 4A" group

  Scenario: Remove role from the group
    Given the following groups:
    | displayName | cn      |
    | Class 4A    | class4a |
    | Class 6B    | class6b |
    And a new role with name "Teacher" and which is joined to the "Class 6B" group
    And I am set the "Teacher" role for "pavel"
    And I am on the group page with "Class 6B"
    Then I should see "Student (Example school 1)" on the "Other roles"
    And I should see "Teacher (Example school 1)" on the "Roles and members"
    And I should see "Pavel Taylor" on the "Roles and members"
    And the memberUid should include "pavel" on the "Class 6B" group
    When I follow "Remove" on the "Teacher" role
    Then I should see "Teacher (Example school 1)" on the "Other roles"
    And I should not see "Teacher" on the "Roles and members"
    And I should see "Student (Example school 1)" on the "Other roles"
    And I should not see "Pavel Taylor" on the "Roles and members"
    And the memberUid should not include "pavel" on the "Class 6B" group

  Scenario: Listing groups
    Given the following groups:
    | displayName | cn      |
    | Class 4A    | class4a |
    | Class 6B    | class6b |
    And I am on the groups list page
    Then I should see "Class 4A"
    And I should see "Class 6B"
    And I should see "Class 1"

  Scenario: Delete group
    Given the following groups:
    | displayName | cn      |
    | Class 4A    | class4a |
    And I am on the group page with "Class 4A"
    When I follow "Destroy"
    Then I should see "Group was successfully destroyed."

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
    Then I should see "Abbveriation include invalid characters (allowed characters is a-z0-9-)"
    When I fill in "Abbreviation" with "class 4a"
    And I press "Create" 
    Then I should see "Abbveriation include invalid characters (allowed characters is a-z0-9-)"
    When I fill in "Abbreviation" with "class-4a"
    And I press "Create" 
    Then I should see "Group was successfully created."
    And I should see "Class 4A"
    And I should see "Example school 1"
    And I should see "class-4a"
