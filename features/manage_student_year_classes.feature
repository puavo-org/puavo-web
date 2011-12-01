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
    Then I should see "1. class"
    And I should see "Student classes: 1A class, 1B class"
    And I follow "Classes"
    Then I should see "1. class"
    And I should see "exampleschool-2011"

  Scenario: Add new student year class with invalid value
    Given the following student year classes:
    | puavoSchoolStartYear | student_class_ids | school           |
    |                 2010 | A                 | Example school 1 |
    And I follow "Example school 1"
    And I follow "Classes"
    And I follow "New class"
    When I fill in "School start year" with "2010"
    And I fill in "student_year_class_student_class_ids_0" with "A"
    And I press "Create"
    Then I should see "Year class cannot be saved!"
    And I should see "School start year has already been taken"
    When I fill in "School start year" with "2011abcd"
    And I press "Create"
    Then I should see "Year class cannot be saved!"
    And I should see "School start year include invalid characters (allowed characters is 0-9)"
    When I fill in "School start year" with "2011"
    And I fill in "student_year_class_student_class_ids_1" with "specialgroup"
    And I press "Create"
    Then I should see "Year class cannot be saved!"
    And I should see "A" within "#student_year_class_student_class_ids_0" a input element
    And I should see "specialgroup" within "#student_year_class_student_class_ids_1" a input element
    And I should see "Class id is too long (maximum is 11 characters)"
    When I fill in "student_year_class_student_class_ids_1" with "B"
    And I press "Create"
    Then I should see "1. class"
    And I should see "Year class was successfully created."
    And I should see "Student classes: 1A class, 1B class"
    When I follow "Classes"
    Then I should see "1. class"
    And I should see "exampleschool-2011"

  Scenario: Edit student year class
    Given the following student year classes:
    | puavoSchoolStartYear | student_class_ids | school           |
    |                 2011 | A                 | Example school 1 |
    |                 2010 | A                 | Example school 1 |
    |                 2009 | A                 | Example school 1 |
    And I follow "Example school 1"
    And I follow "Classes"
    And I edit the 1st student year class
    Then I should see "A" within "#student_year_class_student_class_ids_0" a input element
    When I fill in "School start year" with "2009"
    And I fill in "student_year_class_student_class_ids_1" with "B"
    And I press "Update"
    Then I should see "Year class cannot be saved!"
    And I should see "School start year has already been taken"

    And I should see "A" within "#student_year_class_student_class_ids_0" a input element
    And I should see "B" within "#student_year_class_student_class_ids_1" a input element

    When I fill in "School start year" with "2008"
    And I press "Update"

    Then I should see "4. class"
    And I should see "Student classes: 4A class, 4B class"
    When I follow "Classes"
    Then I should see "exampleschool-2008"
    
  Scenario: Edit student year class without modification
    Given the following student year classes:
    | puavoSchoolStartYear | student_class_ids | school           |
    |                 2011 | A                 | Example school 1 |
    |                 2010 | A                 | Example school 1 |
    |                 2009 | A                 | Example school 1 |
    And I follow "Example school 1"
    And I follow "Classes"
    And I edit the 1st student year class
    And I press "Update"
    Then I should not see "Year class cannot be saved!"
    And I should see "1. class"

  Scenario: List of student year class
    Given the following student year classes:
    | puavoSchoolStartYear | student_class_ids | school           |
    |                 2011 | A                 | Example school 1 |
    |                 2010 | A,B,C             | Example school 1 |
    |                 2009 | A,B               | Example school 1 |
    And I follow "Example school 1"
    And I follow "Classes"
    Then I should see "1. class"
    And I should see "exampleschool-2011"
    And I should see "1A class"
    And I should see "exampleschool-2011a"
    And I should see "2. class"
    And I should see "exampleschool-2010"
    And I should see "2A class"
    And I should see "exampleschool-2010a"
    And I should see "2B class"
    And I should see "exampleschool-2010b"
    And I should see "2C class"
    And I should see "exampleschool-2010c"
    And I should see "3. class"
    And I should see "exampleschool-2009"
    And I should see "3A class"
    And I should see "exampleschool-2009a"
    And I should see "3B class"
    And I should see "exampleschool-2009b"
    
