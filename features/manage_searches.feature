Feature: Search users
  In order to could find a user quickly
  User
  wants search other users by name

  Background:
    Given a new school and group with names "Example school 1", "Class 1" on the "example" organisation
    And the following users:
      | givenName | sn       | uid      | password | school_admin | puavoEduPersonAffiliation |
      | Pavel     | Taylor   | pavel    | secret   | true         | admin                     |
      | Johnny    | Harris   | johnny   | secret   | false        | student                   |
      | Harry     | Johnson  | harry    | secret   | false        | student                   |
      | Jack      | Walker   | jack     | secret   | false        | student                   |
      | Kelly     | Williams | kelly    | secret   | false        | student                   |
      | Eric      | Williams | eric     | secret   | false        | student                   |
      | Anthony   | Davis    | anthony  | secret   | false        | student                   |
      | Isabella  | Jackson  | isabella | secret   | false        | student                   |
    And I am logged in as "pavel" with password "secret"

  Scenario: Find user by first name
    When I search user with "eric"
    Then I should see "Williams, Eric"
    And I should see the following search results:
    | Name           | School name      |
    | Williams, Eric | Example school 1 |

  Scenario: Find user by surname
    When I search user with "williams"
    Then I should see "Williams, Eric"
    And I should see "Williams, Kelly"
    And I should see the following search results:
    | Name            | School name      |
    | Williams, Eric  | Example school 1 |
    | Williams, Kelly | Example school 1 |

  Scenario: Find user by surname and first name
    When I search user with "joh har"
    And I should see the following search results:
    | Name           | School name      |
    | Harris, Johnny | Example school 1 |
    | Johnson, Harry | Example school 1 |
    When I search user with "joh harry"
    And I should see the following search results:
    | Name           | School name      |
    | Johnson, Harry | Example school 1 |

  Scenario: School admin should not find students from other schools
    Given a new school and group with names "Example school 2", "Class 1" on the "example" organisation
    And the following users:
      | givenName | sn    | uid       | password | school_admin | puavoEduPersonAffiliation | school           |
      | Elizabeth | Jones | elizabeth | secret   | false        | student                   | Example school 2 |
    When I search user with "Elizabeth"
    And I should get no search results
