Feature: Search users
  In order to could find a user quickly
  User
  wants search other users by name
  
  Background:
    Given the following schools:
    | displayName      | cn            |
    | Example school 1 | exampleschool |
    And the following roles:
    | displayName | cn      | puavoEduPersonAffiliation |
    | Student     | student | student                   |
    | Teacher     | teacher | teacher                   |
    | Staff       | staff   | staff                     |
    And the following student year classes:
    | puavoSchoolStartYear | student_class_ids | school           |
    |                 2011 | A                 | Example school 1 |
    And the following users:
      | givenName | sn       | uid       | password | school_admin | student_class | roles   | school           |
      | Pavel     | Taylor   | pavel     | secret   | true         |               | Staff   | Example school 1 |
      | Johnny    | Harris   | johnny    | secret   | false        | 1A class      | Student | Example school 1 |
      | Harry     | Johnson  | harry     | secret   | false        | 1A class      | Student | Example school 1 |
      | Jack      | Walker   | jack      | secret   | false        | 1A class      | Student | Example school 1 |
      | Kelly     | Williams | kelly     | secret   | false        | 1A class      | Student | Example school 1 |
      | Eric      | Williams | eric      | secret   | false        | 1A class      | Student | Example school 1 |
      | Anthony   | Davis    | anthony   | secret   | false        | 1A class      | Student | Example school 1 |
      | Isabella  | Jackson  | isabella  | secret   | false        | 1A class      | Student | Example school 1 |
      | Elizabeth | Jones    | elizabeth | secret   | false        | 1A class      | Student | Example school 1 |
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

