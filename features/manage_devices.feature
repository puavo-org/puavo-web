Feature: Manage devices

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

  Scenario: Add new printer to Puavo
    Given I am on the new printer device page
    When I fill in "Hostname" with "testprinter01"
    And I press "Create"
    Then I should see "Device was successfully created."
