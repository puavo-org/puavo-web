Feature: Manage student year classes
  In order to [goal]
  [stakeholder]
  wants [behaviour]

  Background:
    # And the following users:
    #  | givenName | sn     | uid   | password | school_admin | role_name | puavoEduPersonAffiliation |
    #  | Pavel     | Taylor | pavel | secret   | true         | Staff     | Staff                     |
    # And I am logged in as "pavel" with password "secret"
    Given the following schools:
    | displayName      | cn            | puavoClassNamingScheme                       |
    | Example school 1 | exampleschool | #{class_number}. Class (start #{start_year}) |
    And I am logged in as "example" organisation owner
  
  Scenario: Add new student year class
    Given I follow "Example school 1"
    And I follow "Classes"
    And I follow "New class"
    When I fill in "School start year" with "2011"
    And I fill in "student_class_id_0" with "A"
    And I fill in "student_class_id_1" with "B"
    And I press "Create"
    Then I should see "1. Class (start 2011)"
    And I should see "Student classes: 1A Class, 1B Class"
    And I follow "Classes"
    Then I should see "1. Class (start 2011)"
    And I should see "exampleschool-opp-2011"
