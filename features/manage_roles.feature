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

  Scenario: Delete role
    Given the following roles:
    | displayName | cn      | eduPersonAffiliation |
    | Student     | student | student              |
    | Teacher     | teacher | teacher              | 
    When I delete the 1st role
    Then I shout see the following roles:
    | Teacher |

  Scenario: Listing roles
    Given the following roles:
    | displayName | cn      | eduPersonAffiliation |
    | Student     | student | student              |
    | Teacher     | teacher | teacher              | 
    And I follow "Roles"
    Then I should see "Student"
    And I should see "Teacher"
