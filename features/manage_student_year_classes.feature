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
    And I fill in "student_year_class_student_class_ids_0" with "A"
    And I fill in "student_year_class_student_class_ids_1" with "B"
    And I press "Create"
    Then I should see "1. Class (start 2011)"
    And I should see "Student classes: 1A Class, 1B Class"
    And I follow "Classes"
    Then I should see "1. Class (start 2011)"
    And I should see "exampleschool-student-2011"

  Scenario: Edit student year class
    Given the following student year classes:
    | puavoSchoolStartYear | student_class_ids | school           |
    |                 2011 | A                 | Example school 1 |
    |                 2010 | A                 | Example school 1 |
    |                 2009 | A                 | Example school 1 |
    And I follow "Example school 1"
    And I follow "Classes"
    And I edit the 1st student year class
    When I fill in "School start year" with "2008"
    And I fill in "student_year_class_student_class_ids_1" with "B"
    And I press "Update"
    Then I should see "4. Class (start 2008)"
    And I should see "Student classes: 4A Class, 4B Class"
    When I follow "Classes"
    Then I should see "exampleschool-student-2008"
    
