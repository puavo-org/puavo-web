Feature: Manage roles
  In order to [goal]
  [stakeholder]
  wants [behaviour]

  Background:
    Given a new school and group with names "Example school 1", "Class 1" on the "example" organisation
    And the following roles:
    | displayName |
    | Staff       |
    And the following users:
      | givenName | sn     | uid   | password | school_admin | role_name | puavoEduPersonAffiliation |
      | Pavel     | Taylor | pavel | secret   | true         | Staff     | Staff                     |
    And I am logged in as "pavel" with password "secret"
  
  Scenario: Register new role
    Given I am on the new role page
    When I fill in "Role name" with "Student"
    And I press "Create"
    Then I should see "Student"
    When I follow "New role"
    Then I should be on the new role page

  Scenario: Register new role without name
    Given I am on the new role page
    And I press "Create"
    Then I should see "Failed to create role!"
    And I should see "Role name can't be blank"

  Scenario: Edit role and set empty name
    Given the following roles:
    | displayName |
    | Student     |
    And I am on the edit role page with "Student"
    When I fill in "Role name" with ""
    And I press "Update"
    Then I should see "Role cannot be saved!"


  Scenario: Listing roles
    Given the following roles:
    | displayName |
    | Student     |
    | Teacher     |
    And I am on the roles list page
    Then I should see "Student"
    And I should see "Teacher"

  Scenario: Add group to the role
    Given the following roles:
    | displayName |
    | Student     |
    | Teacher     |
    And I am set the "Student" role for "pavel"
    And the following groups:
    | displayName | cn      |
    | Class 4A    | class4a |
    | Class 6B    | class6b |
    And I am on the show role page with "Student"
    When I follow "Add" on the "Class 4A" group
    Then I should see "Group was added to role."
    And I should see "Class 4A (Example school 1)" on the "Member groups"
    And I should not see "Class 4A" on the "Other groups"
    And I should see "Class 6B (Example school 1)" on the "Other groups"
    And I should see "Pavel Taylor" on the "Members"
    And the memberUid should include "pavel" on the "Class 4A" group

  Scenario: Remove group from the role
    Given the following groups:
    | displayName | cn      |
    | Class 4A    | class4a |
    | Class 6B    | class6b |
    And a new role with name "Student" and which is joined to the "Class 4A" group
    And a new role with name "Teacher" and which is joined to the "Class 6B" group
    And I am set the "Student" role for "pavel"
    And I am on the show role page with "Student"
    Then I should see "Class 4A (Example school 1)" on the "Member groups"
    And I should not see "Class 4A" on the "Other groups"
    And I should see "Class 6B (Example school 1)" on the "Other groups"
    And the memberUid should include "pavel" on the "Class 4A" group
    When I follow "Remove" on the "Class 4A" group
    Then I should see "Group was removed from the role."
    And I should not see "Class 4A" on the "Member groups"
    And I should see "Class 4A (Example school 1)" on the "Other groups"
    And I should see "Class 6B (Example school 1)" on the "Other groups"
    And I should see "Pavel Taylor" on the "Members"
    And the memberUid should not include "pavel" on the "Class 4A" group

