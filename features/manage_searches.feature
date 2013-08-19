Feature: Search users
  In order to could find a user quickly
  User
  wants search other users by name

  Background:
    Given a new school and group with names "Example school 1", "Class 1" on the "example" organisation
    And a new role with name "Class 1A" and which is joined to the "Class 1" group
    And the following roles:
    | displayName |
    | Staff       |
    And the following users:
      | givenName | sn       | uid       | password | school_admin | role_name | puavoEduPersonAffiliation |
      | Pavel     | Taylor   | pavel     | secret   | true         | Staff     | Staff                     |
      | Johnny    | Harris   | johnny    | secret   | false        | Class 1A   | Student                   |
      | Harry     | Johnson  | harry     | secret   | false        | Class 1A   | Student                   |
      | Jack      | Walker   | jack      | secret   | false        | Class 1A   | Student                   |
      | Kelly     | Williams | kelly     | secret   | false        | Class 1A   | Student                   |
      | Eric      | Williams | eric      | secret   | false        | Class 1A   | Student                   |
      | Anthony   | Davis    | anthony   | secret   | false        | Class 1A   | Student                   |
      | Isabella  | Jackson  | isabella  | secret   | false        | Class 1A   | Student                   |
    And I am logged in as "pavel" with password "secret"

  Scenario: Find user by first name
    When I search user with "eric"
    Then I should see "Williams Eric"
    And I should see the following search results:
    | Name          | School name      |
    | Williams Eric | Example school 1 |

  Scenario: Find user by surname
    When I search user with "williams"
    Then I should see "Williams Eric"
    And I should see "Williams Kelly"
    And I should see the following search results:
    | Name           | School name      |
    | Williams Eric  | Example school 1 |
    | Williams Kelly | Example school 1 |

  Scenario: Find user by surname and first name
    When I search user with "joh har"
    And I should see the following search results:
    | Name          | School name      |
    | Harris Johnny | Example school 1 |
    | Johnson Harry | Example school 1 |
    When I search user with "joh harry"
    And I should see the following search results:
    | Name          | School name      |
    | Johnson Harry | Example school 1 |

  Scenario: School admin should not find students from other schools
    Given a new school and group with names "Example school 2", "Class 1" on the "example" organisation
    And a new role with name "Class 1A" and which is joined to the "Class 1" group
    And the following roles:
    | displayName |
    | Staff       |
    And the following users:
      | givenName | sn       | uid       | password | school_admin | role_name | puavoEduPersonAffiliation |
      | Elizabeth | Jones    | elizabeth | secret   | false        | Class 1A   | Student                   |
    When I search user with "Elizabeth"
    And I should get no search results
