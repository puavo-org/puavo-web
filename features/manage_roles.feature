Feature: Manage roles
  In order to [goal]
  [stakeholder]
  wants [behaviour]

  Background:
    And I am logged in as "example" organisation owner
  
  Scenario: Register new role
    Given I am on the new role page
    When I fill in "Role name" with "Student"
    And I fill in "Group name" with "student"
    And I select "Teacher" from "Affiliation"
    And I select "Staff" from "Affiliation"
    And I select "Visitor" from "Affiliation"
    And I select "Parent" from "Affiliation"
    And I select "Test user" from "Affiliation"
    And I select "Admin" from "Affiliation"
    And I select "Student" from "Affiliation"
    And I press "Create"
    Then I should see "Role name: Student"
    And I should see "Group name: student"
    And I should see "Affiliation: Student"
    When I follow "New role"
    Then I should be on the new role page

  Scenario: Register new role without name
    Given I am on the new role page
    And I press "Create"
    Then I should see "Failed to create role!"
    And I should see "Role name can't be blank"

  Scenario: Edit role and set empty name
    Given the following roles:
    | displayName | cn      | eduPersonAffiliation |
    | Student     | student | student              |
    | Teacher     | teacher | teacher              | 
    And I edit the 1st role
    When I fill in "Role name" with ""
    And I press "Update"
    Then I should see "Role cannot be saved!"
    When I fill in "Role name" with "Staff"
    And I fill in "Group name" with "staff"
    And I select "Staff" from "Affiliation"
    And I press "Update"
    Then I should see "Role name: Staff"
    And I should see "Group name: staff"
    And I should see "Affiliation: Staff"


  Scenario: Listing roles
    Given the following roles:
    | displayName | cn      | eduPersonAffiliation |
    | Student     | student | student              |
    | Teacher     | teacher | teacher              | 
    And I follow "Roles"
    Then I should see "Student"
    And I should see "Teacher"

  Scenario: Add group to the role
    Given the following roles:
    | displayName |
    | Student     |
    | Teacher     |
    And I am set the "Student" role for "ben"
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
    And I should see "Ben Mabey" on the "Members"
    And the memberUid should include "ben" on the "Class 4A" group
    When I follow "Ben Mabey"
    Then I should be on the user page

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

  Scenario: Move users to other school and role
    Given the following groups:
    | displayName | cn      |
    | Class 6     | class6  |
    And a new role with name "Class 6" and which is joined to the "Class 6" group
    And the following users:
    | givenName | sn     | uid  | password | role_name | puavoEduPersonAffiliation |
    | Joe       | Bloggs | joe  | secret   | Class 6   | Student                   |
    | Jane      | Doe    | jane | secret   | Class 6   | Student                   |
    And a new school and group with names "Example school 2", "Class 7" on the "example" organisation
    And a new role with name "Class 7" and which is joined to the "Class 7" group
    And I am on the show role page with "Class 6"
    And "pavel" is a school admin on the "Example school 2" school
    Then I should see "Class 6"
    When I follow "Move users to another school"
    Then I should see "Select new school"
    When I select "Example school 2" from "new_school"
    And I press "Next"
    Then I should see "Select new role"
    When I select "Class 7" from "new_role"
    And I press "Move users"
    Then I should see "User(s) school has been changed!"
    And the sambaPrimaryGroupSID attribute should contain "Example school 2" of "joe"
    And the homeDirectory attribute should contain "Example school 2" of "joe"
    And the gidNumber attribute should contain "Example school 2" of "joe"
    And the puavoSchool attribute should contain "Example school 2" of "joe"
    And the memberUid should include "joe" on the "Example school 2" school
    And the member should include "joe" on the "Example school 2" school
    And the memberUid should not include "joe" on the "Example school 1" school
    And the member should not include "joe" on the "Example school 1" school
    And the memberUid should include "joe" on the "Class 7" group
    And the member should include "joe" on the "Class 7" group
    And the memberUid should not include "joe" on the "Class 6" group
    And the member should not include "joe" on the "Class 6" group
    And the memberUid should include "joe" on the "Class 7" role
    And the member should include "joe" on the "Class 7" role
    And the memberUid should not include "joe" on the "Class 6" role
    And the member should not include "joe" on the "Class 6" role
